import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _maxImageBytes = 5 * 1024 * 1024;
const _maxTotalBytes = 20 * 1024 * 1024;
const _maxImages = 20;
const _imageTimeout = Duration(seconds: 5);
const _timeBudget = Duration(seconds: 15);

Future<Map<String, Uint8List>> loadMarkdownPdfImages(
  Iterable<String> sources, {
  http.Client? client,
}) async {
  final queue = sources.toSet().take(_maxImages).toList();
  final images = <String, Uint8List>{};
  if (queue.isEmpty) return images;
  final httpClient = client ?? http.Client();
  final elapsed = Stopwatch()..start();
  var next = 0;
  var totalBytes = 0;
  var totalPixels = 0;
  final downloadBudget = _DownloadBudget();

  Future<void> loadNext() async {
    while (next < queue.length && totalBytes < _maxTotalBytes) {
      final remaining = _timeBudget - elapsed.elapsed;
      if (remaining <= Duration.zero) return;
      final source = queue[next++];
      try {
        if (source.length > _maxImageBytes * 4 ~/ 3 + 128) continue;
        final uri = Uri.tryParse(source);
        if (uri == null) continue;
        Uint8List? bytes;
        if (uri.scheme == 'data') {
          final data = uri.data;
          if (data == null ||
              !data.isBase64 ||
              !{
                'image/png',
                'image/jpeg',
                'image/jpg',
              }.contains(data.mimeType)) {
            continue;
          }
          bytes = data.contentAsBytes();
        } else if (_isRemoteImage(uri)) {
          if (downloadBudget.exhausted) continue;
          bytes = await _download(
            httpClient,
            uri,
            remaining < _imageTimeout ? remaining : _imageTimeout,
            downloadBudget,
          );
        }
        if (bytes == null || bytes.length > _maxImageBytes) continue;
        final pixels = _imagePixelCount(bytes);
        if (pixels == null ||
            totalPixels + pixels > 12000000 ||
            totalBytes + bytes.length > _maxTotalBytes) {
          continue;
        }
        totalBytes += bytes.length;
        totalPixels += pixels;
        images[source] = bytes;
      } on Exception {
        // Unavailable images should not prevent saving the rest of a note.
      }
    }
  }

  try {
    await Future.wait(
      List.generate(queue.length.clamp(1, 4), (_) => loadNext()),
    );
  } finally {
    elapsed.stop();
    if (client == null) httpClient.close();
  }
  return images;
}

bool _isRemoteImage(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

class _DownloadBudget {
  var receivedBytes = 0;

  bool get exhausted => receivedBytes >= _maxTotalBytes;

  bool receive(int length) {
    receivedBytes += length;
    return receivedBytes <= _maxTotalBytes;
  }
}

Future<Uint8List?> _download(
  http.Client client,
  Uri uri,
  Duration timeout,
  _DownloadBudget budget,
) async {
  final abort = Completer<void>();
  final timer = Timer(timeout, abort.complete);
  final elapsed = Stopwatch()..start();
  try {
    for (var redirect = 0; redirect <= 3; redirect++) {
      if (!_isRemoteImage(uri) || budget.exhausted) return null;
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(timeout - elapsed.elapsed);
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null) return null;
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200 ||
          budget.exhausted ||
          (response.contentLength ?? 0) > _maxImageBytes) {
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      await for (final chunk in response.stream.timeout(remaining)) {
        if (!budget.receive(chunk.length) ||
            elapsed.elapsed >= timeout ||
            bytes.length + chunk.length > _maxImageBytes) {
          return null;
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
  } finally {
    timer.cancel();
    elapsed.stop();
    if (!abort.isCompleted) abort.complete();
  }
  return null;
}

int? _imagePixelCount(Uint8List bytes) {
  int? allowed(int width, int height) =>
      width > 0 &&
          height > 0 &&
          width <= 6000 &&
          height <= 6000 &&
          width * height <= 12000000
      ? width * height
      : null;

  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10 &&
      bytes[12] == 0x49 &&
      bytes[13] == 0x48 &&
      bytes[14] == 0x44 &&
      bytes[15] == 0x52) {
    final data = ByteData.sublistView(bytes);
    return allowed(data.getUint32(16), data.getUint32(20));
  }
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  var offset = 2;
  while (offset + 3 < bytes.length) {
    if (bytes[offset++] != 0xff) return null;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset + 2 >= bytes.length) return null;
    final marker = bytes[offset++];
    if (marker == 0xd9 || marker == 0xda) return null;
    if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) continue;
    final length = bytes[offset] * 256 + bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    if ({0xc0, 0xc1, 0xc2}.contains(marker)) {
      if (length < 8) return null;
      return allowed(
        bytes[offset + 5] * 256 + bytes[offset + 6],
        bytes[offset + 3] * 256 + bytes[offset + 4],
      );
    }
    offset += length;
  }
  return null;
}
