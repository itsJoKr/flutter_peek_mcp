import '../filters.dart';
import '../mcp_server.dart';
import '../noise_filter.dart';
import '../vm_client.dart';

/// Tries to connect. When that fails but buffers hold data from an earlier
/// run (for example, the app crashed), returns a warning instead of throwing
/// so the tool can still answer from the buffers.
Future<String?> connectOrWarn(VmClient vm) async {
  try {
    await vm.ensureConnected();
    return null;
  } catch (e) {
    if (vm.logs.isEmpty && vm.httpRequests.isEmpty) rethrow;
    return 'Showing data buffered before the app disconnected. '
        'Connection error: $e';
  }
}

ToolDef isAppConnectedTool(VmClient vm) => ToolDef(
      name: 'is_app_connected',
      description:
          'Check whether the Flutter app is reachable through the Dart VM '
          'service, and how much log and HTTP data is buffered. Call this '
          'first if other tools fail, or to get setup instructions.',
      inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
      handler: (args) async {
        String? error;
        try {
          await vm.ensureConnected();
        } catch (e) {
          error = '$e';
        }
        return {
          'connected': vm.isConnected,
          if (vm.connectedUri != null) 'vmServiceUri': vm.connectedUri,
          'uriSource': vm.uriSource,
          'bufferedLogs': vm.logs.length,
          'bufferedHttpRequests': vm.httpRequests.length,
          if (error != null) 'error': error,
        };
      },
    );

ToolDef connectTool(VmClient vm) => ToolDef(
      name: 'connect',
      description: 'Connect to a specific Dart VM service URI, such as the '
          '"A Dart VM Service on … is available at: http://127.0.0.1:PORT/TOKEN=/" '
          'line that `flutter run` prints, or a DevTools URL. Use this when the '
          'app was started without --vmservice-out-file. Call with no uri to go '
          'back to reading the URI file.',
      readOnly: false,
      inputSchema: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'VM service URI (http://, ws:// or a DevTools URL)',
          },
        },
      },
      handler: (args) async {
        await vm.connectTo(args['uri'] as String?);
        return {
          'connected': vm.isConnected,
          'vmServiceUri': vm.connectedUri,
          'uriSource': vm.uriSource,
        };
      },
    );

ToolDef clearBuffersTool(VmClient vm) => ToolDef(
      name: 'clear_buffers',
      description:
          'Delete all buffered logs and HTTP requests. Call this before you '
          'reproduce a bug, so later queries only show the relevant activity.',
      readOnly: false,
      inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
      handler: (args) async {
        final logsCleared = vm.logs.length;
        final httpCleared = vm.httpRequests.length;
        vm.clearBuffers();
        return {'logsCleared': logsCleared, 'httpCleared': httpCleared};
      },
    );

ToolDef contextAroundTool(VmClient vm, NoiseFilter noise) => ToolDef(
      name: 'get_context_around',
      description:
          'Logs and HTTP requests interleaved by time in a window around a '
          'moment. Center the window on a timestamp, a log id or an HTTP '
          'request id. Use it to see what happened around an error in one call.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'timestampMs': {
            'type': 'integer',
            'description': 'Center of the window (Unix ms)',
          },
          'logId': {
            'type': 'string',
            'description': 'Center on this console log entry',
          },
          'httpId': {
            'type': 'string',
            'description': 'Center on the start of this HTTP request',
          },
          'windowMs': {
            'type': 'integer',
            'default': 10000,
            'description': 'Half-width of the window on each side',
          },
          'includeNoise': {'type': 'boolean', 'default': false},
        },
      },
      handler: (args) async {
        final warning = await connectOrWarn(vm);
        final centerMs = _centerOf(vm, args);
        final windowMs = asInt(args['windowMs']) ?? 10000;
        final includeNoise = args['includeNoise'] as bool? ?? false;
        final window = {
          'sinceMs': centerMs - windowMs,
          'untilMs': centerMs + windowMs,
          'includeNoise': includeNoise,
        };

        final items = [
          for (final log in filterLogs(vm.logs, window))
            {'kind': 'log', ...log.toPreview()},
          for (final request in filterHttp(vm.httpRequests, window, noise))
            {'kind': 'http', ...request.toPreview()},
        ]..sort(
            (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

        return {
          if (warning != null) 'warning': warning,
          'centerMs': centerMs,
          'windowMs': windowMs,
          'returned': items.length,
          'items': items,
        };
      },
    );

int _centerOf(VmClient vm, Map<String, dynamic> args) {
  final timestamp = asInt(args['timestampMs']);
  if (timestamp != null) return timestamp;

  final logId = args['logId'] as String?;
  if (logId != null) {
    final index = vm.indexOfLog(logId);
    if (index < 0) {
      throw ToolException('No console log with id "$logId" in buffer');
    }
    return vm.logs[index].timestamp.millisecondsSinceEpoch;
  }

  final httpId = args['httpId'] as String?;
  if (httpId != null) {
    final entry = vm.httpById(httpId);
    if (entry == null) {
      throw ToolException('No HTTP request with id "$httpId" in buffer');
    }
    return entry.timestamp.millisecondsSinceEpoch;
  }

  throw ToolException('Pass one of timestampMs, logId or httpId');
}
