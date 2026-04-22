import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/mission_control/data/mc_bridge_client.dart';

/// A minimal fake HttpClientAdapter that captures the last outbound request
/// and returns a canned response. Good enough for verifying we speak the
/// JSON-RPC 2.0 protocol correctly without booting a real HTTP server.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions, Map<String, dynamic> decodedBody)
      responder;
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastBody;

  _FakeAdapter(this.responder);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    final rawBody = options.data is String ? options.data as String : '';
    lastBody = rawBody.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawBody) as Map).cast<String, dynamic>();
    return responder(options, lastBody!);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> payload, {int status = 200}) {
  final body = utf8.encode(jsonEncode(payload));
  return ResponseBody.fromBytes(
    body,
    status,
    headers: const {
      'content-type': ['application/json'],
    },
  );
}

ResponseBody _sseResponse(Map<String, dynamic> payload, {int status = 200}) {
  final body = utf8.encode('event: message\ndata: ${jsonEncode(payload)}\n\n');
  return ResponseBody.fromBytes(
    body,
    status,
    headers: const {
      'content-type': ['text/event-stream'],
    },
  );
}

void main() {
  group('McBridgeClient.basicAuth', () {
    test('base64-encodes username:password', () {
      expect(
        McBridgeClient.basicAuth('clawmine', 'hunter2'),
        'Basic ${base64Encode(utf8.encode('clawmine:hunter2'))}',
      );
    });
  });

  group('tools/list round-trip', () {
    test('sends JSON-RPC 2.0, parses tools[]', () async {
      int callCount = 0;
      final adapter = _FakeAdapter((options, body) {
        callCount++;
        final method = body['method'] as String?;
        if (method == 'initialize') {
          return _jsonResponse({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'protocolVersion': '2025-06-18',
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'openclaw', 'version': '2026.4.5'},
            },
          });
        }
        if (method == 'notifications/initialized') {
          return _jsonResponse({'jsonrpc': '2.0', 'result': null});
        }
        if (method == 'tools/list') {
          return _jsonResponse({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'tools': [
                {
                  'name': 'execute_command',
                  'description': 'Run a shell command',
                  'inputSchema': {'type': 'object'},
                },
                {'name': 'list_tasks'},
              ],
            },
          });
        }
        return _jsonResponse({'error': 'unexpected method'}, status: 500);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final client = McBridgeClient(
        Uri.parse('https://t-abc.opspocket.com/mcp'),
        basicAuthHeader:
            McBridgeClient.basicAuth('clawmine', 'secret'),
        dio: dio,
      );

      final tools = await client.listTools();
      expect(tools, hasLength(2));
      expect(tools.first.name, 'execute_command');
      expect(callCount, greaterThanOrEqualTo(2));

      // Check the last request had the Authorization header and JSON-RPC shape.
      final headers = adapter.lastRequest!.headers;
      expect(headers['Authorization'], startsWith('Basic '));
      expect(adapter.lastBody!['jsonrpc'], '2.0');
      expect(adapter.lastBody!['method'], 'tools/list');
      expect(adapter.lastBody!['id'], isA<int>());
    });
  });

  group('tools/call', () {
    test('extracts text from content[0].text, surfaces isError', () async {
      final adapter = _FakeAdapter((options, body) {
        if (body['method'] == 'initialize' ||
            body['method'] == 'notifications/initialized') {
          return _jsonResponse(
            {'jsonrpc': '2.0', 'id': body['id'], 'result': {}},
          );
        }
        return _jsonResponse({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'content': [
              {'type': 'text', 'text': 'hello world'},
            ],
            'isError': false,
          },
        });
      });

      final client = McBridgeClient(
        Uri.parse('https://t.opspocket.com/mcp'),
        dio: Dio()..httpClientAdapter = adapter,
      );
      final res = await client.callTool('ping', {});
      expect(res.text, 'hello world');
      expect(res.isError, false);
    });

    test('parses SSE-framed responses', () async {
      final adapter = _FakeAdapter((options, body) {
        if (body['method'] == 'initialize' ||
            body['method'] == 'notifications/initialized') {
          return _jsonResponse(
            {'jsonrpc': '2.0', 'id': body['id'], 'result': {}},
          );
        }
        return _sseResponse({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'content': [
              {'type': 'text', 'text': 'streamed'},
            ],
          },
        });
      });

      final client = McBridgeClient(
        Uri.parse('https://t.opspocket.com/mcp'),
        dio: Dio()..httpClientAdapter = adapter,
      );
      final res = await client.callTool('long_running', {});
      expect(res.text, 'streamed');
    });

    test('maps 401 to a clear auth error', () async {
      final adapter = _FakeAdapter((options, body) {
        return ResponseBody.fromBytes(
          utf8.encode('<html>Unauthorized</html>'),
          401,
          headers: const {
            'content-type': ['text/html'],
            'www-authenticate': ['Basic realm="claw"'],
          },
        );
      });

      final client = McBridgeClient(
        Uri.parse('https://t.opspocket.com/mcp'),
        dio: Dio()..httpClientAdapter = adapter,
      );
      expect(
        () => client.listTools(),
        throwsA(isA<McBridgeException>().having(
            (e) => e.message, 'message', contains('Auth rejected'),),),
      );
    });

    test('surfaces JSON-RPC error objects', () async {
      final adapter = _FakeAdapter((options, body) {
        if (body['method'] == 'initialize' ||
            body['method'] == 'notifications/initialized') {
          return _jsonResponse(
            {'jsonrpc': '2.0', 'id': body['id'], 'result': {}},
          );
        }
        return _jsonResponse({
          'jsonrpc': '2.0',
          'id': body['id'],
          'error': {'code': -32601, 'message': 'Method not found'},
        });
      });

      final client = McBridgeClient(
        Uri.parse('https://t.opspocket.com/mcp'),
        dio: Dio()..httpClientAdapter = adapter,
      );
      expect(
        () => client.callTool('nope', {}),
        throwsA(isA<McBridgeException>().having((e) => e.message,
            'message', contains('Method not found'),),),
      );
    });
  });
}
