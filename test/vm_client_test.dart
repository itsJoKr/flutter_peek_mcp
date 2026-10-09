@Timeout(Duration(seconds: 90))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_peek_mcp/src/dtd_discovery.dart';
import 'package:flutter_peek_mcp/src/models.dart';
import 'package:flutter_peek_mcp/src/vm_client.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service_io.dart';

import 'fixtures/fake_dtd.dart';

/// Runs test/fixtures/sample_app.dart with the VM service (and DDS) enabled
/// and checks what VmClient captures from it.
void main() {
  late Directory temp;
  late Process app;
  late VmClient vm;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('flutter_peek_test');
    final uriFile = File('${temp.path}/vm_service.json');
    app = await Process.start(Platform.resolvedExecutable, [
      'run',
      '--observe=0',
      '--write-service-info=${uriFile.uri}',
      'test/fixtures/sample_app.dart',
    ]);
    unawaited(app.stdout.drain<void>());
    unawaited(app.stderr.drain<void>());
    await _waitFor(() => uriFile.existsSync() && uriFile.lengthSync() > 0);

    vm = VmClient(
      uriFilePath: uriFile.path,
      httpPollInterval: const Duration(milliseconds: 200),
    )..startBackgroundReconnect();
    await _waitFor(() => _orders(vm).length >= 3);
  });

  tearDownAll(() async {
    await vm.dispose();
    app.kill();
    await app.exitCode;
    await temp.delete(recursive: true);
  });

  test('captures completed requests with bodies and redacted headers', () {
    final order = _orders(vm).first;
    expect(order.method, 'POST');
    expect(order.statusCode, 201);
    expect(order.durationMs, isNotNull);
    expect(order.requestHeaders['authorization'], '<redacted>');
    expect(order.requestBody, contains('ORD-'));
    expect(order.toDetail()['responseBody'], isA<Map>());
  });

  test('fetches binary bodies only on demand', () async {
    final image = vm.httpRequests.firstWhere(
      (e) => e.url.endsWith('/logo.png') && e.completed,
    );
    expect(image.contentType, 'image/png');
    expect(image.responseBody, isNull);

    final loaded = await vm.loadBodies(image.id);
    expect(loaded!.responseBody, '<8 bytes of binary data>');
  });

  test('keeps identical lines printed in the same millisecond', () {
    final lines = vm.logs.where((l) => l.text == 'duplicate line').toList();
    expect(lines.length, greaterThanOrEqualTo(2));
    expect(lines.length.isEven, isTrue);
  });

  test('resolves the error and stack trace of log() records', () async {
    await _waitFor(() => vm.logs.any((l) => l.text.contains('#0')));
    final record = vm.logs.firstWhere((l) => l.text.contains('#0'));
    expect(record.source, 'log');
    expect(record.level, 'error');
    expect(record.text, contains('[sample] tick'));
    expect(record.text, contains('Bad state: boom'));
  });

  test('reconnecting to the same app duplicates nothing', () async {
    final logIds = vm.logs.map((l) => l.text).toList();
    final firstLine = logIds.first;
    final countBefore = vm.logs.where((l) => l.text == firstLine).length;

    await vm.connectTo(null);
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(vm.logs.where((l) => l.text == firstLine).length, countBefore);
    final profileIds = vm.httpRequests.map((e) => e.profileId).toList();
    expect(profileIds.toSet().length, profileIds.length);
  });

  group('without a URI file', () {
    late Directory dtdDir;
    late String project;
    late FakeDtd dtd;
    final sep = Platform.pathSeparator;

    Future<VmClient> clientFindingApps({String? uriFile}) async {
      final client = VmClient(
        uriFilePath: uriFile ?? '${temp.path}${sep}missing.txt',
        discovery: DtdDiscovery(
          directory: dtdDir.path,
          workingDirectory: project,
        ),
      );
      addTearDown(client.dispose);
      return client;
    }

    setUp(() async {
      dtdDir = await Directory('${temp.path}${sep}dtd').create();
      project = '${temp.path}${sep}project';
    });

    tearDown(() async {
      await dtd.stop();
      await dtdDir.delete(recursive: true);
    });

    test('finds the app through the Dart Tooling Daemon', () async {
      dtd = await FakeDtd.start(
        directory: dtdDir,
        workspaceRoot: project,
        vmServices: [
          {'uri': vm.connectedUri!, 'name': 'Kind: Dart - Package: sample'},
        ],
      );
      final client = await clientFindingApps();

      await client.ensureConnected();

      expect(client.connectedUri, vm.connectedUri);
      expect(client.uriSource, 'Dart Tooling Daemon');
      expect(client.appName, 'Kind: Dart - Package: sample');
    });

    test('looks past a URI file left behind by a stopped app', () async {
      dtd = await FakeDtd.start(
        directory: dtdDir,
        workspaceRoot: project,
        vmServices: [
          {'uri': vm.connectedUri!},
        ],
      );
      final stale = File('${temp.path}${sep}stale.txt');
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      await stale.writeAsString('http://127.0.0.1:${closed.port}/gone=/');
      await closed.close();
      final client = await clientFindingApps(uriFile: stale.path);

      await client.ensureConnected();

      expect(client.connectedUri, vm.connectedUri);
      expect(client.uriSource, 'Dart Tooling Daemon');
    });

    test('lists several apps of the project instead of picking one', () async {
      dtd = await FakeDtd.start(
        directory: dtdDir,
        workspaceRoot: project,
        vmServices: [
          {'uri': vm.connectedUri!, 'name': 'Kind: Flutter - Device: iPhone'},
          {
            'uri': 'ws://127.0.0.1:1/other=/ws',
            'name': 'Kind: Flutter - Device: Pixel'
          },
        ],
      );
      final client = await clientFindingApps();

      await expectLater(
        client.ensureConnected(),
        throwsA(isA<VmConnectionException>()
            .having(
                (e) => e.message, 'message', contains('Found 2 running apps'))
            .having((e) => e.message, 'message', contains('Device: Pixel'))
            .having((e) => e.message, 'message', contains(vm.connectedUri!))),
      );
      expect(client.isConnected, isFalse);
    });

    test('names apps running in other folders but does not connect', () async {
      dtd = await FakeDtd.start(
        directory: dtdDir,
        workspaceRoot: '${temp.path}${sep}other_project',
        vmServices: [
          {'uri': vm.connectedUri!, 'name': 'Kind: Dart - Package: other'},
        ],
      );
      final client = await clientFindingApps();

      await expectLater(
        client.ensureConnected(),
        throwsA(isA<VmConnectionException>()
            .having(
                (e) => e.message, 'message', contains('No running app found'))
            .having((e) => e.message, 'message', contains('Package: other'))),
      );
      expect(client.isConnected, isFalse);
    });
  });

  test('does not hang while the app is paused at a breakpoint', () async {
    final debugger = await vmServiceConnectUri(vm.connectedUri!);
    final isolateId = (await debugger.getVM()).isolates!.first.id!;
    final image = vm.httpRequests.lastWhere(
      (e) => e.url.endsWith('/logo.png') && e.completed,
    );
    await debugger.pause(isolateId);
    try {
      final stopwatch = Stopwatch()..start();
      final loaded = await vm.loadBodies(image.id);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
      expect(loaded!.responseBody, isNull);
    } finally {
      await debugger.resume(isolateId);
      await debugger.dispose();
    }
  });
}

List<HttpEntry> _orders(VmClient vm) => vm.httpRequests
    .where((e) => e.url.endsWith('/orders') && e.requestBody != null)
    .toList();

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within 30 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
