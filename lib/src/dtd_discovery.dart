import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'vm_uri.dart';

/// How the folder that a Dart Tooling Daemon was started in relates to the
/// folder that flutter-peek runs in (the agent's project).
enum WorkspaceMatch {
  /// The daemon was started in the project or in a folder inside it, as
  /// `flutter run` in the project (or in `example/app` of a monorepo) does.
  project,

  /// The project is inside the folder the daemon was started in, for example
  /// an IDE workspace that holds several projects.
  parent,

  /// Somewhere else.
  none,
}

/// A running app that a Dart Tooling Daemon knows about.
class DiscoveredApp {
  /// The app's VM service, as a `ws://…/ws` URI.
  final String vmServiceUri;

  /// For example `Kind: Flutter - Device: macOS - Package: aisle`.
  final String? name;

  /// The folder the daemon was started in.
  final String workspaceRoot;

  final WorkspaceMatch match;

  DiscoveredApp({
    required this.vmServiceUri,
    required this.name,
    required this.workspaceRoot,
    required this.match,
  });

  /// One line for messages to the agent.
  String describe() =>
      '${name ?? 'unnamed app'} (started in $workspaceRoot): $vmServiceUri';
}

/// Finds running apps through the Dart Tooling Daemon (DTD), so the app needs
/// no `--vmservice-out-file`.
///
/// Since Dart 3.12 (Flutter 3.44), every DTD writes a file named after its pid
/// to `<Dart data home>/dtd`. The file holds its WebSocket URI and the folder
/// it was started in; `dart tooling-daemon --list` reads the same files.
/// `flutter run` starts a DTD, and DDS registers the app's VM service with it,
/// so asking each DTD for `ConnectedApp.getVmServices` lists the running apps.
/// A daemon deletes its file when it exits.
class DtdDiscovery {
  /// The folder with the DTD files, or null when it can't be determined.
  final String? directory;

  /// The project folder that apps are matched against.
  final String workingDirectory;

  /// Per daemon, for connecting and for its answer.
  final Duration timeout;

  DtdDiscovery({
    String? directory,
    String? workingDirectory,
    this.timeout = const Duration(seconds: 2),
  })  : directory = directory ?? dtdDirectory(Platform.environment),
        workingDirectory = workingDirectory ?? Directory.current.path;

  /// Every app registered with a running DTD, best match first. Daemons that
  /// don't answer (for example, one that crashed and left its file behind)
  /// are skipped.
  Future<List<DiscoveredApp>> findApps() async {
    final daemons = await _readDaemonFiles();
    final perDaemon = await Future.wait(daemons.map(_appsOf));

    final byUri = <String, DiscoveredApp>{};
    for (final app in perDaemon.expand((apps) => apps)) {
      final existing = byUri[app.vmServiceUri];
      if (existing == null || app.match.index < existing.match.index) {
        byUri[app.vmServiceUri] = app;
      }
    }
    return byUri.values.toList()
      ..sort((a, b) => a.match.index.compareTo(b.match.index));
  }

  Future<List<_DaemonFile>> _readDaemonFiles() async {
    final dir = directory;
    if (dir == null) return const [];
    final folder = Directory(dir);
    if (!await folder.exists()) return const [];

    final daemons = <_DaemonFile>[];
    try {
      // A cap, so a folder full of leftovers can't slow every connection
      // attempt down.
      await for (final entity in folder.list().take(64)) {
        if (entity is! File) continue;
        final daemon = _DaemonFile.parse(await entity.readAsString());
        if (daemon != null) daemons.add(daemon);
      }
    } on FileSystemException {
      // Unreadable folder or file; discovery is a convenience.
    }
    return daemons;
  }

  Future<List<DiscoveredApp>> _appsOf(_DaemonFile daemon) async {
    final List<Map<String, dynamic>> services;
    try {
      services = await _getVmServices(daemon.wsUri);
    } catch (_) {
      return const [];
    }
    final match = workspaceMatch(workingDirectory, daemon.workspaceRoot);
    return [
      for (final service in services)
        if (service['uri'] is String)
          DiscoveredApp(
            vmServiceUri: toWebSocketUri(service['uri'] as String),
            name: service['name'] as String?,
            workspaceRoot: daemon.workspaceRoot,
            match: match,
          ),
    ];
  }

  /// One JSON-RPC call over the daemon's WebSocket. `package:dtd` does the
  /// same, but brings a large set of dependencies with it.
  Future<List<Map<String, dynamic>>> _getVmServices(String wsUri) async {
    final socket = await WebSocket.connect(wsUri).timeout(timeout);
    try {
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': '1',
        'method': 'ConnectedApp.getVmServices',
      }));
      await for (final message in socket.timeout(timeout)) {
        final reply = message is String ? jsonDecode(message) : null;
        if (reply is! Map || '${reply['id']}' != '1') continue;
        final result = reply['result'];
        final services = result is Map ? result['vmServices'] : null;
        if (services is! List) return const [];
        return services
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      }
      return const [];
    } finally {
      unawaited(socket.close());
    }
  }
}

class _DaemonFile {
  final String wsUri;
  final String workspaceRoot;

  _DaemonFile(this.wsUri, this.workspaceRoot);

  static _DaemonFile? parse(String contents) {
    try {
      final json = jsonDecode(contents);
      if (json is! Map) return null;
      final wsUri = json['wsUri'];
      if (wsUri is! String || wsUri.isEmpty) return null;
      final root = json['workspaceRoot'];
      return _DaemonFile(wsUri, root is String ? root : '');
    } on FormatException {
      return null;
    }
  }
}

/// The folder where each Dart Tooling Daemon writes its file: `dtd` in the
/// Dart data home, which `package:dart_data_home` in the Dart SDK defines as
///
/// - `$DART_DATA_HOME`, when set;
/// - `%LOCALAPPDATA%\Dart` on Windows;
/// - `~/Library/Application Support/Dart` on macOS;
/// - `$XDG_STATE_HOME/Dart`, or `~/.local/state/Dart`, on Linux.
String? dtdDirectory(Map<String, String> environment) {
  String? nonEmpty(String name) {
    final value = environment[name];
    return value == null || value.isEmpty ? null : value;
  }

  final sep = Platform.pathSeparator;
  final override = nonEmpty('DART_DATA_HOME');
  if (override != null) return '${_trimSeparators(override)}${sep}dtd';

  final String? base;
  if (Platform.isWindows) {
    final localAppData = nonEmpty('LOCALAPPDATA');
    base = localAppData == null ? null : '$localAppData${sep}Dart';
  } else {
    final home = nonEmpty('HOME');
    if (Platform.isMacOS) {
      base = home == null ? null : '$home/Library/Application Support/Dart';
    } else {
      final state = nonEmpty('XDG_STATE_HOME') ??
          (home == null ? null : '$home/.local/state');
      base = state == null ? null : '$state/Dart';
    }
  }
  return base == null ? null : '$base${sep}dtd';
}

/// How [workspaceRoot] (where a daemon started) relates to [project].
///
/// A daemon started in the file system root or the home folder says nothing
/// about the project, so it never counts as [WorkspaceMatch.parent].
WorkspaceMatch workspaceMatch(String project, String workspaceRoot) {
  if (workspaceRoot.isEmpty) return WorkspaceMatch.none;
  final projectPath = _comparable(project);
  final root = _comparable(workspaceRoot);
  if (_isWithin(projectPath, root)) return WorkspaceMatch.project;

  final sep = Platform.pathSeparator;
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  // `/`, or a Windows drive such as `C:` (without a separator once trimmed).
  final isRoot = root == sep || !root.contains(sep);
  final tooBroad =
      isRoot || (home != null && home.isNotEmpty && root == _comparable(home));
  if (!tooBroad && _isWithin(root, projectPath)) return WorkspaceMatch.parent;
  return WorkspaceMatch.none;
}

bool _isWithin(String parent, String path) =>
    path == parent || path.startsWith('$parent${Platform.pathSeparator}');

/// Both macOS and Windows file systems ignore case by default.
String _comparable(String path) {
  final trimmed = _trimSeparators(path);
  return Platform.isMacOS || Platform.isWindows
      ? trimmed.toLowerCase()
      : trimmed;
}

String _trimSeparators(String path) {
  var result = path;
  while (result.length > 1 && result.endsWith(Platform.pathSeparator)) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
