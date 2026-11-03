import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:itou_md/services/markdown_pdf_images.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aW5cAAAAASUVORK5CYII=',
);

void main() {
  test('embeds data PNG and JPEG without making requests', () async {
    final jpeg = await File('assets/logo/emfont_logo.jpg').readAsBytes();
    final pngSource = 'data:image/png;base64,${base64Encode(_png)}';
    final jpegSource = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    final client = MockClient(
      (_) async => throw StateError('Unexpected request'),
    );
    final images = await loadMarkdownPdfImages([
      pngSource,
      jpegSource,
    ], client: client);
    expect(images[pngSource], _png);
    expect(images[jpegSource], jpeg);
  });

  test('deduplicates downloads and does not attach credentials', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.headers['authorization'], isNull);
      expect(request.headers['cookie'], isNull);
      return http.Response.bytes(_png, 200);
    });
    final images = await loadMarkdownPdfImages([
      'https://example.com/image.png',
      'https://example.com/image.png',
      'file:///private/image.png',
      'https://user:secret@example.com/image.png',
      'data:image/svg+xml;base64,${base64Encode(utf8.encode('<svg/>'))}',
    ], client: client);
    expect(requests, 1);
    expect(images.keys, ['https://example.com/image.png']);
  });

  test(
    'missing, invalid, and oversized images preserve successful downloads',
    () async {
      final oversized = Uint8List.fromList(_png);
      ByteData.sublistView(oversized).setUint32(16, 100000);
      final client = MockClient(
        (request) async => switch (request.url.path) {
          '/missing' => http.Response('', 404),
          '/invalid' => http.Response('<svg/>', 200),
          '/dimensions' => http.Response.bytes(oversized, 200),
          '/offline' => throw const SocketException('offline'),
          _ => http.Response.bytes(_png, 200),
        },
      );
      final images = await loadMarkdownPdfImages([
        for (final path in [
          'missing',
          'invalid',
          'dimensions',
          'offline',
          'valid',
        ])
          'https://example.com/$path',
        'data:image/png;base64,invalid!',
      ], client: client);
      expect(images.keys, ['https://example.com/valid']);
    },
  );

  test(
    'follows safe redirects and rejects file or credential redirects',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return switch (request.url.path) {
          '/safe' => http.Response('', 302, headers: {'location': '/image'}),
          '/file' => http.Response(
            '',
            302,
            headers: {'location': 'file:///private/image.png'},
          ),
          '/auth' => http.Response(
            '',
            302,
            headers: {'location': 'https://user:secret@example.com/image'},
          ),
          _ => http.Response.bytes(_png, 200),
        };
      });
      final images = await loadMarkdownPdfImages([
        'https://example.com/safe',
        'https://example.com/file',
        'https://example.com/auth',
      ], client: client);
      expect(images.keys, ['https://example.com/safe']);
      expect(paths.where((path) => path == '/image'), hasLength(1));
    },
  );

  test('stops oversized streams before reading the entire response', () async {
    var cancelled = false;
    late StreamController<List<int>> stream;
    stream = StreamController<List<int>>(
      onListen: () {
        stream.add(Uint8List(5 * 1024 * 1024));
        stream.add([0]);
      },
      onCancel: () => cancelled = true,
    );
    final client = MockClient.streaming(
      (request, body) async => http.StreamedResponse(stream.stream, 200),
    );
    final images = await loadMarkdownPdfImages([
      'https://example.com/large',
    ], client: client);
    expect(images, isEmpty);
    expect(cancelled, isTrue);
    await stream.close();
  });

  test('limits the number of images fetched for a document', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response.bytes(_png, 200);
    });
    final images = await loadMarkdownPdfImages([
      for (var i = 0; i < 25; i++) 'https://example.com/$i.png',
    ], client: client);
    expect(requests, 20);
    expect(images, hasLength(20));
  });

  test('limits the aggregate decoded image size', () async {
    final largePng = Uint8List.fromList(_png);
    final dimensions = ByteData.sublistView(largePng);
    dimensions.setUint32(16, 4000);
    dimensions.setUint32(20, 3000);
    final client = MockClient((_) async => http.Response.bytes(largePng, 200));
    final images = await loadMarkdownPdfImages([
      'https://example.com/first.png',
      'https://example.com/second.png',
    ], client: client);
    expect(images, hasLength(1));
    expect(images.values.single, largePng);
  });

  test(
    'rejected concurrent downloads still consume the shared byte budget',
    () async {
      var requests = 0;
      var receivedBytes = 0;
      const imageBytes = 5 * 1024 * 1024;
      final client = MockClient.streaming((request, body) async {
        requests++;
        Stream<List<int>> response() async* {
          receivedBytes += imageBytes;
          yield Uint8List(imageBytes);
        }

        return http.StreamedResponse(response(), 200);
      });
      final images = await loadMarkdownPdfImages([
        for (var i = 0; i < 20; i++) 'https://example.com/invalid$i.png',
      ], client: client);
      expect(images, isEmpty);
      expect(receivedBytes, 20 * 1024 * 1024);
      expect(requests, 4);
    },
  );

  test(
    'times out stalled image streams and cancels the subscription',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = MockClient.streaming(
        (request, body) async => http.StreamedResponse(stream.stream, 200),
      );
      final images = await loadMarkdownPdfImages([
        'https://example.com/stalled',
      ], client: client);
      expect(images, isEmpty);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );
}
