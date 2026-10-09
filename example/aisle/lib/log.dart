import 'dart:developer' as developer;

/// A named logger that writes through `dart:developer` `log()`.
///
/// Tools that read the VM service (DevTools, flutter-peek) get the level, the
/// logger name, and the full error with its stack trace in one entry.
class Log {
  const Log(this.name);

  final String name;

  void info(String message) => developer.log(message, name: name, level: 800);

  void warning(String message) =>
      developer.log(message, name: name, level: 900);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      developer.log(
        message,
        name: name,
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
}
