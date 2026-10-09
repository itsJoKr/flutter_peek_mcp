import 'dart:convert';
import 'dart:io';

/// A stand-in for a Dart Tooling Daemon. It answers
/// `ConnectedApp.getVmServices` with [vmServices] and writes its discovery
/// file to a folder, the way `dart tooling-daemon` does.
class FakeDtd {
  final HttpServer _server;
  final File file;

  FakeDtd._(this._server, this.file);

  static Future<FakeDtd> start({
    required Directory directory,
    required String workspaceRoot,
    required List<Map<String, String>> vmServices,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        final call = jsonDecode(message as String) as Map;
        socket.add(jsonEncode({
          'jsonrpc': '2.0',
          'id': call['id'],
          'result': {'type': 'VmServicesResponse', 'vmServices': vmServices},
        }));
      });
    });

    final file =
        File('${directory.path}${Platform.pathSeparator}${server.port}');
    await file.writeAsString(jsonEncode({
      'wsUri': 'ws://127.0.0.1:${server.port}/token${server.port}=',
      'epoch': DateTime.now().millisecondsSinceEpoch,
      'pid': server.port,
      'dartVersion': Platform.version,
      'workspaceRoot': workspaceRoot,
    }));
    return FakeDtd._(server, file);
  }

  Future<void> stop() => _server.close(force: true);
}
