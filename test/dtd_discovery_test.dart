import 'dart:convert';
import 'dart:io';

import 'package:flutter_peek_mcp/src/dtd_discovery.dart';
import 'package:test/test.dart';

import 'fixtures/fake_dtd.dart';

void main() {
  final sep = Platform.pathSeparator;
  late Directory temp;
  late Directory dtdDir;
  late String project;
  final daemons = <FakeDtd>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flutter_peek_dtd');
    dtdDir = await Directory('${temp.path}${sep}dtd').create();
    project = '${temp.path}${sep}project';
  });

  tearDown(() async {
    for (final daemon in daemons) {
      await daemon.stop();
    }
    daemons.clear();
    await temp.delete(recursive: true);
  });

  Future<void> startDaemon(String workspaceRoot, String port) async {
    daemons.add(await FakeDtd.start(
      directory: dtdDir,
      workspaceRoot: workspaceRoot,
      vmServices: [
        {
          'uri': 'http://127.0.0.1:$port/abc=/',
          'name': 'Kind: Flutter - Device: macOS - Package: app$port',
        },
      ],
    ));
  }

  DtdDiscovery discovery() => DtdDiscovery(
        directory: dtdDir.path,
        workingDirectory: project,
      );

  group('findApps', () {
    test('finds an app started in a folder inside the project', () async {
      await startDaemon('$project${sep}example${sep}app', '1111');

      final apps = await discovery().findApps();

      expect(apps, hasLength(1));
      expect(apps.single.vmServiceUri, 'ws://127.0.0.1:1111/abc=/ws');
      expect(apps.single.name, contains('Package: app1111'));
      expect(apps.single.match, WorkspaceMatch.project);
    });

    test('ranks the project, then parent folders, then everything else',
        () async {
      await startDaemon('${temp.path}${sep}elsewhere', '3333');
      await startDaemon(temp.path, '2222');
      await startDaemon(project, '1111');

      final apps = await discovery().findApps();

      expect(apps.map((a) => a.match), [
        WorkspaceMatch.project,
        WorkspaceMatch.parent,
        WorkspaceMatch.none,
      ]);
      expect(apps.first.vmServiceUri, contains(':1111/'));
    });

    test('skips files left behind by daemons that are gone', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await File('${dtdDir.path}${sep}99999').writeAsString(jsonEncode({
        'wsUri': 'ws://127.0.0.1:$port/gone=',
        'pid': 99999,
        'workspaceRoot': project,
      }));
      await File('${dtdDir.path}${sep}notes.txt').writeAsString('not json');
      await startDaemon(project, '1111');

      final apps = await discovery().findApps();

      expect(apps.map((a) => a.vmServiceUri), ['ws://127.0.0.1:1111/abc=/ws']);
    });

    test('returns nothing when the folder does not exist', () async {
      final missing = DtdDiscovery(
        directory: '${temp.path}${sep}missing',
        workingDirectory: project,
      );
      expect(await missing.findApps(), isEmpty);
    });
  });

  group('workspaceMatch', () {
    final base = '${sep}work';
    final app = '$base${sep}app';

    test('the project folder or one inside it', () {
      expect(workspaceMatch(app, app), WorkspaceMatch.project);
      expect(workspaceMatch(app, '$app$sep'), WorkspaceMatch.project);
      expect(workspaceMatch(app, '$app${sep}example'), WorkspaceMatch.project);
    });

    test('a folder that contains the project', () {
      expect(workspaceMatch(app, base), WorkspaceMatch.parent);
    });

    test('a sibling folder with the same prefix', () {
      expect(workspaceMatch(app, '${app}2'), WorkspaceMatch.none);
    });

    test('the root, the home folder or an unknown folder', () {
      expect(workspaceMatch(app, sep), WorkspaceMatch.none);
      expect(workspaceMatch(app, ''), WorkspaceMatch.none);
      final home =
          Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
      if (home != null) {
        expect(workspaceMatch('$home${sep}app', home), WorkspaceMatch.none);
      }
    });
  });

  group('dtdDirectory', () {
    test('DART_DATA_HOME overrides the default', () {
      expect(dtdDirectory({'DART_DATA_HOME': '${sep}data$sep'}),
          '${sep}data${sep}dtd');
    });

    test('the Dart data home of this platform', () {
      if (Platform.isWindows) {
        expect(
            dtdDirectory({'LOCALAPPDATA': r'C:\Local'}), r'C:\Local\Dart\dtd');
      } else if (Platform.isMacOS) {
        expect(dtdDirectory({'HOME': '/Users/me'}),
            '/Users/me/Library/Application Support/Dart/dtd');
      } else {
        expect(dtdDirectory({'HOME': '/home/me'}),
            '/home/me/.local/state/Dart/dtd');
        expect(dtdDirectory({'HOME': '/home/me', 'XDG_STATE_HOME': '/state'}),
            '/state/Dart/dtd');
      }
    });

    test('null without the variables it needs', () {
      expect(dtdDirectory({}), isNull);
    });
  });
}
