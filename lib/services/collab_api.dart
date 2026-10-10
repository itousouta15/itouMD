import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A token-free server origin and a case-sensitive room. Never persist credentials,
/// query strings or arbitrary paths as a collaboration endpoint.
class CollabEndpoint {
  final Uri server;
  final String room;

  const CollabEndpoint._(this.server, this.room);

  factory CollabEndpoint.parse(String address, String room) {
    final input = address.trim();
    final uri = Uri.tryParse(input);
    if (uri == null ||
        input.length > 2048 ||
        RegExp(r'[\s\\]').hasMatch(input) ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        input.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('請輸入 http(s) 伺服器來源，不含帳密、路徑、查詢參數或片段。');
    }
    if (room.isEmpty ||
        room.length > 64 ||
        RegExp(r'[^a-zA-Z0-9_-]').hasMatch(room)) {
      throw const FormatException('房間名稱限 1–64 個英文字母、數字、底線或連字號，區分大小寫。');
    }
    return CollabEndpoint._(Uri.parse(uri.origin), room);
  }

  Uri get documentUri =>
      server.replace(path: '/api/document', queryParameters: {'room': room});
  String get key =>
      base64Url.encode(utf8.encode(jsonEncode([server.toString(), room])));
}

class CollabSnapshot {
  final String room;
  final String content;
  final String revision;
  final bool pending;

  const CollabSnapshot({
    required this.room,
    required this.content,
    required this.revision,
    this.pending = false,
  });

  factory CollabSnapshot.fromJson(dynamic json, String room) {
    if (json is! Map<String, dynamic> ||
        json['room'] != room ||
        json['content'] is! String ||
        json['revision'] is! String ||
        (json['revision'] as String).isEmpty ||
        (json['revision'] as String).length > 128 ||
        json['pending'] is! bool) {
      throw const CollabException('伺服器回應格式不正確，草稿已保留。');
    }
    return CollabSnapshot(
      room: room,
      content: json['content'],
      revision: json['revision'],
      pending: json['pending'],
    );
  }

  Map<String, dynamic> toJson() => {
    'room': room,
    'content': content,
    'revision': revision,
    'pending': pending,
  };
}

class CollabException implements Exception {
  final String message;
  const CollabException(this.message);
  @override
  String toString() => message;
}

class CollabConflict extends CollabException {
  final CollabSnapshot current;
  const CollabConflict(this.current) : super('伺服器版本已變更。');
}

class CollabApi {
  final CollabEndpoint endpoint;
  final http.Client _client;
  final Duration timeout;

  CollabApi(
    this.endpoint, {
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  Future<CollabSnapshot> get() => _request('GET');
  Future<CollabSnapshot> put(String content, String revision) {
    if (utf8.encode(content).length > 1024 * 1024) {
      throw const CollabException('原型的快照上限為 1 MiB；請先另存新檔。');
    }
    return _request('PUT', {'content': content, 'revision': revision});
  }

  Future<CollabSnapshot> _request(
    String method, [
    Map<String, String>? body,
  ]) async {
    try {
      final request = http.Request(method, endpoint.documentUri)
        ..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode != 200 && response.statusCode != 409) {
        throw CollabException(
          response.statusCode == 413
              ? '文件超過伺服器快照上限；草稿已保留。'
              : '協作伺服器回應 ${response.statusCode}，請檢查伺服器後重試。',
        );
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 409) {
        if (json is! Map<String, dynamic>) throw const FormatException();
        throw CollabConflict(
          CollabSnapshot.fromJson(json['current'], endpoint.room),
        );
      }
      return CollabSnapshot.fromJson(json, endpoint.room);
    } on CollabException {
      rethrow;
    } on FormatException {
      throw const CollabException('伺服器回應格式不正確，草稿已保留。');
    } catch (_) {
      // Do not surface exception URLs (or accidentally include user-supplied credentials).
      throw const CollabException('無法連到協作伺服器或連線逾時。可離線編輯，稍後按同步重試。');
    }
  }

  void close() => _client.close();
}
