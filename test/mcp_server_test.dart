import 'dart:io';

import 'package:flutter_peek_mcp/src/mcp_server.dart';
import 'package:flutter_peek_mcp/src/version.dart';
import 'package:test/test.dart';

void main() {
  final server = McpServer(
    name: 'test',
    version: '1.0.0',
    instructions: 'Use the tools.',
    tools: [
      ToolDef(
        name: 'echo',
        description: 'Echoes its arguments',
        inputSchema: {'type': 'object'},
        handler: (args) async => args,
      ),
      ToolDef(
        name: 'fail',
        description: 'Always fails',
        inputSchema: {'type': 'object'},
        readOnly: false,
        handler: (args) async => throw ToolException('nope'),
      ),
    ],
  );

  Future<Map<String, dynamic>?> send(String method, [Map? params]) =>
      server.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params != null) 'params': params,
      });

  test('initialize negotiates a supported protocol version', () async {
    final known = await send('initialize', {'protocolVersion': '2025-03-26'});
    expect(known!['result']['protocolVersion'], '2025-03-26');
    expect(known['result']['instructions'], 'Use the tools.');

    final unknown = await send('initialize', {'protocolVersion': '1999-01-01'});
    expect(unknown!['result']['protocolVersion'],
        McpServer.supportedProtocolVersions.first);
  });

  test('notifications get no response', () async {
    expect(
      await server
          .handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      isNull,
    );
  });

  test('tools/list includes read-only hints', () async {
    final tools = (await send('tools/list'))!['result']['tools'] as List;
    expect(tools.map((t) => t['name']), ['echo', 'fail']);
    expect(tools.last['annotations'], {'readOnlyHint': false});
  });

  test('tools/call returns JSON text', () async {
    final response = await send('tools/call', {
      'name': 'echo',
      'arguments': {'a': 1}
    });
    expect(response!['result']['content'][0]['text'], contains('"a": 1'));
  });

  test('tool failures are reported as tool errors', () async {
    final response = await send('tools/call', {'name': 'fail'});
    expect(response!['result']['isError'], isTrue);
    expect(response['result']['content'][0]['text'], 'Error: nope');
  });

  test('protocol errors use JSON-RPC codes', () async {
    expect((await send('tools/call', {'name': 'missing'}))!['error']['code'],
        JsonRpcException.invalidParams);
    expect((await send('bogus'))!['error']['code'],
        JsonRpcException.methodNotFound);
  });

  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('\nversion: $packageVersion\n'));
  });
}
