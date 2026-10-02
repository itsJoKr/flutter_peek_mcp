import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef ToolHandler = Future<Object?> Function(Map<String, dynamic> args);

class ToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final ToolHandler handler;

  /// Tells the client the tool only reads data.
  final bool readOnly;

  const ToolDef({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.readOnly = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': {'readOnlyHint': readOnly},
      };
}

/// A tool failure whose message is shown to the agent as is.
class ToolException implements Exception {
  final String message;
  ToolException(this.message);

  @override
  String toString() => message;
}

class JsonRpcException implements Exception {
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  final int code;
  final String message;
  JsonRpcException(this.code, this.message);

  @override
  String toString() => message;
}

/// Minimal MCP server: JSON-RPC 2.0 over newline-delimited stdio, tools only.
///
/// stdout carries the protocol, so all diagnostics go to stderr. Requests are
/// handled concurrently, so a slow tool doesn't block a `ping`.
class McpServer {
  static const supportedProtocolVersions = [
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  ];

  final String name;
  final String version;
  final String? instructions;
  final List<ToolDef> tools;

  McpServer({
    required this.name,
    required this.version,
    required this.tools,
    this.instructions,
  });

  /// Serves stdin/stdout until stdin closes, then gives requests that are
  /// still running up to [drainTimeout] to answer.
  Future<void> run(
      {Duration drainTimeout = const Duration(seconds: 10)}) async {
    stderr.writeln('$name $version: listening on stdio');
    final done = Completer<void>();
    final inFlight = <Future<void>>{};
    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        final request = _handleLine(line);
        inFlight.add(request);
        unawaited(request.whenComplete(() => inFlight.remove(request)));
      },
      onDone: done.complete,
      onError: (Object e) => stderr.writeln('$name: stdin error: $e'),
    );
    await done.future;
    await Future.wait(inFlight).timeout(drainTimeout, onTimeout: () => []);
  }

  Future<void> _handleLine(String line) async {
    if (line.trim().isEmpty) return;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException catch (e) {
      stderr.writeln('$name: malformed JSON-RPC message: $e');
      return;
    }
    if (message is! Map) return;
    final response = await handle(message.cast<String, dynamic>());
    if (response != null) stdout.writeln(jsonEncode(response));
  }

  /// Handles one JSON-RPC message. Returns null for notifications.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> message) async {
    final id = message['id'];
    final method = message['method'] as String?;
    final params =
        (message['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    final isNotification = id == null;

    try {
      final result = await _dispatch(method, params);
      if (isNotification) return null;
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } catch (e, st) {
      if (isNotification) return null;
      final code =
          e is JsonRpcException ? e.code : JsonRpcException.internalError;
      if (e is! JsonRpcException) {
        stderr.writeln('$name: $method failed: $e\n$st');
      }
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': '$e'},
      };
    }
  }

  Future<Object?> _dispatch(String? method, Map<String, dynamic> params) async {
    if (method != null && method.startsWith('notifications/')) return null;
    switch (method) {
      case 'initialize':
        return _initialize(params);
      case 'ping':
        return const <String, dynamic>{};
      case 'tools/list':
        return {
          'tools': [for (final tool in tools) tool.toJson()]
        };
      case 'tools/call':
        return _callTool(params);
      default:
        throw JsonRpcException(
          JsonRpcException.methodNotFound,
          'Method not found: $method',
        );
    }
  }

  Map<String, dynamic> _initialize(Map<String, dynamic> params) {
    final requested = params['protocolVersion'];
    return {
      'protocolVersion': supportedProtocolVersions.contains(requested)
          ? requested
          : supportedProtocolVersions.first,
      'capabilities': {'tools': <String, dynamic>{}},
      'serverInfo': {'name': name, 'version': version},
      if (instructions != null) 'instructions': instructions,
    };
  }

  Future<Map<String, dynamic>> _callTool(Map<String, dynamic> params) async {
    final toolName = params['name'];
    final tool = tools.where((t) => t.name == toolName).firstOrNull;
    if (tool == null) {
      throw JsonRpcException(
        JsonRpcException.invalidParams,
        'Unknown tool: $toolName',
      );
    }
    final args =
        (params['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
    try {
      final result = await tool.handler(args);
      final text = result is String
          ? result
          : const JsonEncoder.withIndent('  ').convert(result);
      return {
        'content': [
          {'type': 'text', 'text': text},
        ],
      };
    } catch (e) {
      return {
        'content': [
          {'type': 'text', 'text': 'Error: $e'},
        ],
        'isError': true,
      };
    }
  }
}
