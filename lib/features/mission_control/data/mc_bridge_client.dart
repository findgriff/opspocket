import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/secure_storage.dart';
import '../../server_profiles/data/server_profile_repository_impl.dart';

/// MCP JSON-RPC 2.0 client for the OpenClaw 2026.4.5 gateway.
///
/// **Gateway architecture (2026.4.5):**
///   * Control UI + MCP both served from the tenant's Caddy reverse proxy
///     (port 443 on the tenant's public domain, e.g.
///     `https://t-abc123.opspocket.com/`).
///   * OpenClaw binds loopback on `127.0.0.1:18789`; Caddy proxies to it
///     with an HTTP basic-auth wrapper (`auth.mode: none` server-side, so
///     Caddy's basic_auth is the ONLY auth).
///   * MCP speaks JSON-RPC 2.0 at `POST /mcp` relative to the tenant host.
///   * Username: `clawmine`. Password: stored in `/root/CREDENTIALS.json`
///     on the tenant box and mirrored into the iOS Keychain when the user
///     pastes it into the server profile setup.
///
/// Responses may be either `application/json` or `text/event-stream` (the
/// gateway can stream long-running tool calls); both are handled by [_rpc].
///
/// Why MCP (not shell dispatch): structured responses, 30–150ms round-trip,
/// no shell escaping.
class McBridgeClient {
  final Uri endpoint;
  final String? basicAuthHeader; // pre-computed 'Basic <base64>' or null
  final Dio _dio;
  String? _sessionId;
  int _nextId = 0;
  bool _initialised = false;
  List<McBridgeTool>? _tools;

  McBridgeClient(
    this.endpoint, {
    this.basicAuthHeader,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  /// Build the canonical `Authorization: Basic` header value from a username
  /// and password.
  static String basicAuth(String username, String password) {
    final raw = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  /// Perform the MCP `initialize` handshake + `notifications/initialized`.
  /// Safe to call repeatedly — only runs once per client.
  Future<void> ensureInitialised() async {
    if (_initialised) return;
    await _rpc('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {'tools': {}},
      'clientInfo': {'name': 'opspocket', 'version': '1.0'},
    });
    try {
      await _rpc('notifications/initialized', {}, isNotification: true);
    } catch (_) {
      // Non-fatal if the server doesn't implement it.
    }
    _initialised = true;
  }

  /// List available tools, caching for the life of this client.
  Future<List<McBridgeTool>> listTools({bool refresh = false}) async {
    await ensureInitialised();
    if (_tools != null && !refresh) return _tools!;
    final env = await _rpc('tools/list', {});
    final list = (env['result']?['tools'] as List?) ?? [];
    _tools = list
        .whereType<Map>()
        .map((m) => McBridgeTool.fromJson(m.cast<String, dynamic>()))
        .toList();
    return _tools!;
  }

  /// Returns true iff the bridge exposes a tool with [name].
  Future<bool> hasTool(String name) async {
    final tools = await listTools();
    return tools.any((t) => t.name == name);
  }

  /// Convenience: run a shell command through `execute_command`.
  Future<String> runShell(String command, {Duration? timeout}) async {
    final out = await callTool(
      'execute_command',
      {'command': command},
      timeout: timeout,
    );
    try {
      final payload = (jsonDecode(out.text) as Map).cast<String, dynamic>();
      final stdout = (payload['stdout'] as String? ?? '').trim();
      final stderr = (payload['stderr'] as String? ?? '').trim();
      final exit = payload['exitCode'];
      if (exit is int && exit != 0) {
        throw McBridgeException(
          stderr.isNotEmpty ? stderr : (stdout.isNotEmpty ? stdout : 'exit $exit'),
        );
      }
      return stdout.isEmpty ? stderr : stdout;
    } on FormatException {
      return out.text;
    }
  }

  /// Invoke an MCP tool.
  Future<McBridgeToolResult> callTool(
    String name,
    Map<String, dynamic> args, {
    Duration? timeout,
  }) async {
    await ensureInitialised();
    final env = await _rpc(
      'tools/call',
      {'name': name, 'arguments': args},
      timeout: timeout,
    );
    if (env['error'] != null) {
      throw McBridgeException(
        (env['error'] as Map)['message']?.toString() ?? 'bridge error',
      );
    }
    final result = (env['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final contents = (result['content'] as List?) ?? [];
    final text = contents
        .whereType<Map>()
        .map((c) {
          final t = c['type'];
          if (t == 'text') return c['text']?.toString() ?? '';
          if (t == 'resource') return c['resource']?['uri']?.toString() ?? '';
          return '';
        })
        .where((s) => s.isNotEmpty)
        .join('\n');
    return McBridgeToolResult(
      text: text,
      isError: result['isError'] == true,
      structured: (result['structuredContent'] as Map?)?.cast<String, dynamic>(),
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _rpc(
    String method,
    Map<String, dynamic> params, {
    bool isNotification = false,
    Duration? timeout,
  }) async {
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      if (params.isNotEmpty) 'params': params,
      if (!isNotification) 'id': ++_nextId,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      if (basicAuthHeader != null) 'Authorization': basicAuthHeader!,
      if (_sessionId != null) 'Mcp-Session-Id': _sessionId!,
    };

    Response resp;
    try {
      resp = await _dio.postUri(
        endpoint,
        data: jsonEncode(body),
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          receiveTimeout: timeout ?? const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
    } on DioException catch (e) {
      throw McBridgeException('HTTP error: ${e.message ?? e.type}');
    }

    final sid = resp.headers.value('mcp-session-id');
    if (sid != null && sid.isNotEmpty) _sessionId = sid;

    if (isNotification) return {};

    final status = resp.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw McBridgeException(
        'Auth rejected (HTTP $status) — check the clawmine password.',
      );
    }
    if (status >= 400) {
      throw McBridgeException(
        'HTTP $status: ${_firstLine(resp.data?.toString())}',
      );
    }

    final contentType = (resp.headers.value('content-type') ?? '').toLowerCase();
    final raw = resp.data?.toString() ?? '';

    final parsed = contentType.contains('text/event-stream')
        ? _parseSse(raw)
        : _parseJson(raw);

    // JSON-RPC 2.0 error check (server 200s with {error:…} are a thing).
    if (parsed['error'] != null && parsed['result'] == null) {
      final err = (parsed['error'] as Map).cast<String, dynamic>();
      final msg = err['message']?.toString() ?? 'JSON-RPC error';
      final code = err['code'];
      throw McBridgeException(code != null ? '$msg (code $code)' : msg);
    }

    return parsed;
  }

  Map<String, dynamic> _parseJson(String raw) {
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      throw McBridgeException('Unexpected response: ${_firstLine(raw)}');
    }
  }

  /// Parses the first `data:` event payload from an SSE stream body. Multi-
  /// line `data:` lines are concatenated per the SSE spec.
  Map<String, dynamic> _parseSse(String body) {
    final buffer = StringBuffer();
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('data:')) {
        buffer.writeln(line.substring(5).trimLeft());
      } else if (line.isEmpty && buffer.isNotEmpty) {
        break; // end of event
      }
    }
    final payload = buffer.toString().trim();
    if (payload.isEmpty) {
      throw McBridgeException('Empty SSE response');
    }
    try {
      return (jsonDecode(payload) as Map).cast<String, dynamic>();
    } catch (_) {
      throw McBridgeException('Unparseable SSE payload: ${_firstLine(payload)}');
    }
  }

  String _firstLine(String? s) {
    if (s == null || s.isEmpty) return '(empty)';
    final nl = s.indexOf('\n');
    return (nl < 0 ? s : s.substring(0, nl)).trim();
  }
}

class McBridgeTool {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  const McBridgeTool({
    required this.name,
    this.description,
    this.inputSchema = const {},
  });

  factory McBridgeTool.fromJson(Map<String, dynamic> j) => McBridgeTool(
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString(),
        inputSchema: (j['inputSchema'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

class McBridgeToolResult {
  final String text;
  final bool isError;
  final Map<String, dynamic>? structured;

  const McBridgeToolResult({
    required this.text,
    this.isError = false,
    this.structured,
  });
}

class McBridgeException implements Exception {
  final String message;
  McBridgeException(this.message);
  @override
  String toString() => message;
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Keychain key for the per-server clawmine basic-auth password.
String clawmineSecretKey(String serverId) => 'clawmine.pwd.$serverId';

/// Fixed basic-auth username baked into `install-openclaw.sh`.
const String clawmineUsername = 'clawmine';

/// Derives the tenant MCP URL from the server's hostnameOrIp. Null if the
/// profile is missing or empty. Always `https://` — the 2026.4.5 gateway is
/// TLS-only (Caddy terminates TLS; plain HTTP is rejected).
final mcBridgeUrlProvider =
    FutureProvider.family<Uri?, String>((ref, serverId) async {
  final profile = await ref.watch(serverProfileByIdProvider(serverId).future);
  final host = profile?.hostnameOrIp.trim();
  if (host == null || host.isEmpty) return null;
  // Tolerate the user having pasted a full URL or a bare hostname.
  if (host.startsWith('http://') || host.startsWith('https://')) {
    final base = Uri.parse(host);
    return base.replace(path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/mcp');
  }
  return Uri.parse('https://$host/mcp');
});

/// Single bridge client per server. Held for the life of the Riverpod
/// container so the MCP session id survives across calls.
final mcBridgeClientProvider =
    FutureProvider.family<McBridgeClient?, String>((ref, serverId) async {
  final url = await ref.watch(mcBridgeUrlProvider(serverId).future);
  if (url == null) return null;
  final storage = ref.read(secureStorageProvider);
  final password = await storage.read(key: clawmineSecretKey(serverId));
  final auth = (password != null && password.isNotEmpty)
      ? McBridgeClient.basicAuth(clawmineUsername, password)
      : null;
  return McBridgeClient(url, basicAuthHeader: auth);
});
