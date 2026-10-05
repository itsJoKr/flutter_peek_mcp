# flutter_peek_mcp

An [MCP](https://modelcontextprotocol.io) server that lets AI coding agents
(Claude Code, Cursor, Codex, …) read the **console output** and **HTTP
traffic** of your running Flutter app.

It connects to the app through the Dart VM service, the same channel that
DevTools uses. You do not change the app, and you do not add a package to it.

With flutter-peek, the agent can answer questions like these without you
copying and pasting logs:

- "Did any request fail in the last minute?"
- "Find the request whose payload contains order `ORD-1234`."
- "What happened in the logs around that exception?"
- "Show me the full request and response for the last POST to `/checkout`."

**Contents:** [How it works](#how-it-works) ·
[Requirements](#requirements) · [Setup](#setup) · [Usage](#usage) ·
[Tools](#tools) · [What is captured](#what-is-captured) ·
[Buffers and ids](#buffers-and-ids) · [Privacy and security](#privacy-and-security) ·
[Options](#options) · [Limitations](#limitations) ·
[Troubleshooting](#troubleshooting) · [Development](#development)

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/itsJoKr/flutter_peek_mcp/main/doc/architecture-dark.svg">
  <img alt="The Flutter app sends console output and HTTP traffic through the Dart VM service to flutter_peek_mcp, which serves them to the AI agent over MCP (stdio)." src="https://raw.githubusercontent.com/itsJoKr/flutter_peek_mcp/main/doc/architecture-light.svg">
</picture>

1. `flutter run --vmservice-out-file=<file>` writes the VM service URI of the
   app to a file.
2. The agent starts `flutter_peek_mcp`. The server reads the file and
   connects. If the app is not running yet, the server tries again every
   second.
3. The server subscribes to the `Stdout`, `Stderr` and `Logging` streams. It
   also turns on the `dart:io` HTTP profiler (the data source of the DevTools
   Network tab) and reads it every 1.5 seconds.
4. The data goes into in-memory buffers. The agent queries the buffers with
   the [tools](#tools).

The server only reads. It does not pause the app or change its state. It
does two things in the app: it turns on the HTTP profiler, and it calls
`toString()` on the errors that you pass to `log()`, to show them in full.

## Requirements

- Dart SDK 3.10 or later for `dart install` (Flutter 3.38 or later). With Dart
  3.5 to 3.9, install with `dart pub global activate` instead.
- The app must run in **debug** or **profile** mode. Release builds have no VM
  service.
- Android, iOS, macOS, Windows and Linux. Emulators, simulators and physical
  devices all work, because `flutter run` forwards the VM service to your
  computer.
- Flutter web is not supported. See [Limitations](#limitations).

## Setup

### 1. Install

```bash
dart install flutter_peek_mcp
```

`dart install` compiles the server to a native executable, so it starts fast
and does not depend on your Dart SDK version. It prints the folder that it
put the executable in. If that folder is not on your `PATH`, add it, as the
command tells you. If you use FVM, run `fvm dart install flutter_peek_mcp`.

- To update, run the same command again.
- To install a specific version: `dart install flutter_peek_mcp 0.1.0`.
- To install the latest code from GitHub:
  `dart install https://github.com/itsJoKr/flutter_peek_mcp.git`.
- With Dart 3.5 to 3.9: `dart pub global activate flutter_peek_mcp`. This puts
  the executable in `~/.pub-cache/bin`.

<details>
<summary>Alternative: run from a clone</summary>

```bash
git clone https://github.com/itsJoKr/flutter_peek_mcp
cd flutter_peek_mcp
dart pub get
```

Then, in the configs below, use `dart` as the command, with
`["run", "/absolute/path/to/flutter_peek_mcp/bin/flutter_peek_mcp.dart"]` as
the args.

</details>

### 2. Register the server with your agent

**Claude Code**

```bash
claude mcp add flutter-peek -- flutter_peek_mcp
```

Or put it in a `.mcp.json` file at the root of your project to share it with
your team:

```json
{
  "mcpServers": {
    "flutter-peek": {
      "command": "flutter_peek_mcp"
    }
  }
}
```

Run `/mcp` in Claude Code to make sure that `flutter-peek` is connected.

**Cursor**: add the same `mcpServers` entry to `.cursor/mcp.json`.

**Other MCP clients**: start the `flutter_peek_mcp` command with the stdio
transport.

### 3. Run your app with `--vmservice-out-file`

The server finds the app through a file that contains the VM service URI.
Tell `flutter run` to write that file:

```bash
flutter run --vmservice-out-file=/tmp/flutter_peek_vmservice.txt
```

On Windows, the default path is `%TEMP%\flutter_peek_vmservice.txt`.

In your IDE, add the flag to the run arguments:

<details>
<summary>VS Code (<code>.vscode/launch.json</code>)</summary>

```json
{
  "configurations": [
    {
      "name": "app",
      "request": "launch",
      "type": "dart",
      "args": ["--vmservice-out-file=/tmp/flutter_peek_vmservice.txt"]
    }
  ]
}
```

</details>

<details>
<summary>Android Studio / IntelliJ</summary>

Go to **Run → Edit Configurations… → Additional run args**, and add
`--vmservice-out-file=/tmp/flutter_peek_vmservice.txt`.

</details>

That is all. The server finds the app and connects again after a hot restart
or a full restart.

**No flag?** If the app is already running (for example, after
`flutter attach`, which does not have `--vmservice-out-file`), ask the agent
to connect to the VM service URI. `flutter run` and `flutter attach` print it
as `A Dart VM Service on … is available at: http://127.0.0.1:PORT/TOKEN=/`.
The agent calls the `connect` tool with that URI. A DevTools URL also works.

## Usage

Talk to the agent in plain language. It selects the tools. Some examples:

- "Check flutter-peek: did any request fail since I opened the cart?"
- "Search the HTTP traffic for `ORD-1234` and show me the response."
- "Find the last exception in the logs and tell me what caused it."
- "What did the app log and request in the 5 seconds before that 500?"

### Reproduce a bug with a clean buffer

1. Ask the agent to clear the flutter-peek buffers (`clear_buffers`).
2. Reproduce the bug in the app.
3. Ask the agent what went wrong. It sees only the activity of the
   reproduction.

### Tell your agent about it

Agents use MCP tools better when the project instructions mention them. For
example, add this to `CLAUDE.md` or `AGENTS.md`:

```markdown
When a bug involves the running app, use the flutter-peek MCP tools before you
ask me for logs: start with `http_summary` and
`list_console_logs(level: "error")`, then open entries with the `get_*` tools.
```

## Tools

| Tool | Purpose |
|---|---|
| `is_app_connected` | Connection status, buffer sizes and setup hints. |
| `connect(uri?)` | Connect to a VM service URI. With no URI, use the URI file again. |
| `list_http_requests` | Scan requests. Shows metadata only (method, URL, status, duration, content type, sizes). |
| `get_http_request(id)` | One request with full headers and bodies. |
| `get_http_requests_with_bodies` | Up to 10 requests with bodies. A filter is required. |
| `search_http_requests(query)` | Find text in URLs, headers or bodies. |
| `http_summary` | Counts by status and method, error rate, slowest and most frequent URLs. |
| `list_console_logs` | Scan console output. Filter by text, regex, level, source or time. |
| `get_console_log(id)` | Full text of one entry, with the entries around it. |
| `search_console_logs(query)` | grep-style search with context. |
| `get_context_around` | Logs and HTTP requests in time order, around a timestamp, a log entry or a request. |
| `clear_buffers` | Delete the buffered data, to start clean before you reproduce a bug. |

### Parameters

The agent sees the full schema of each tool. These are the parameters that
are useful to know:

| Parameter | Tools | Values |
|---|---|---|
| `status` | HTTP list, bulk | `"404"`, `"4xx"`, `"5xx"`, `">=400"`, `"<300"` |
| `urlContains`, `method` | HTTP list, bulk | Case-insensitive URL substring; `GET`, `POST`, … |
| `sinceMs`, `untilMs` | Most list tools | Unix time in milliseconds. List responses include `nowMs`, so "the last minute" is `sinceMs: nowMs - 60000`. |
| `minDurationMs` | HTTP list, bulk | Only slow requests |
| `level`, `source` | `list_console_logs` | `info`, `warn`, `error`; `stdout`, `stderr`, `log` |
| `includeNoise` | HTTP tools | `true` shows [background traffic](#noise-filter) |
| `maxBodyChars`, `bodyOffset` | `get_http_request` | Read a long body in parts. The default is 20,000 characters for each body. |
| `order`, `limit`, `offset` | List tools | `newest` (default) or `oldest`; paging |

A request preview looks like this:

```json
{
  "id": "19",
  "timestamp": 1790947229771,
  "method": "POST",
  "url": "https://api.example.com/orders",
  "status": 201,
  "durationMs": 182,
  "contentType": "application/json",
  "requestBytes": 20,
  "responseBytes": 48,
  "completed": true
}
```

### Design choices

- **Bodies only on request.** List and search tools return metadata and short
  snippets. Bodies come only from `get_*` tools, and the bulk tool requires a
  filter. This keeps the agent's context small.
- **Responses stay small.** `get_http_request` returns up to 20,000
  characters of each body, and the bulk tool 2,000. A response tells the agent
  when a body was cut and how to read the rest. A complete JSON body is
  returned as JSON, not as an escaped string. Binary bodies are shown as a
  byte count.
- **Images and other binary downloads are not prefetched.** Their bodies
  (and all bodies larger than 1 MB) are fetched only when a tool asks for
  them. This keeps apps with many `Image.network` calls fast.
- **Breakpoints do not block the agent.** While the app is paused in the
  debugger, tools still answer from the buffers. Bodies that were not fetched
  yet stay empty until the app runs again.

## What is captured

### Console

| Source | What writes to it |
|---|---|
| `stdout` | `print`, `debugPrint`, Flutter framework error reports, and logging packages that print (for example, `logger` with its default output) |
| `stderr` | Writes to `stderr` |
| `log` | `log()` from `dart:developer`, with its `name`, `level`, `error` and `stackTrace` |

Each entry gets a level:

- `stderr` is always `error`.
- `log()` uses its `level`: 1000 or more (SEVERE) is `error`, 900 or more
  (WARNING) is `warn`, and other values are `info`.
- `print` lines, and `log()` calls without a level, get `error` when the text
  contains "error" or "exception", and `warn` when it contains "warn".

For the best results, send your logs through `dart:developer` `log()`. Then
the agent gets real levels, logger names, and the full error and stack trace
in one entry. With `package:logging`:

```dart
import 'dart:developer' as developer;
import 'package:logging/logging.dart';

void main() {
  Logger.root.onRecord.listen((record) => developer.log(
        record.message,
        time: record.time,
        level: record.level.value,
        name: record.loggerName,
        error: record.error,
        stackTrace: record.stackTrace,
      ));
  // …
}
```

If you use `logger`, turn off colors (`PrettyPrinter(colors: false)`). ANSI
color codes make the text harder for the agent to read.

`flutter run` starts DDS, which keeps the last 10,000 events of each console
stream. When the server connects, DDS sends it that history. So the agent also sees output from
before the server connected, except output from the first moments of the app.

### HTTP

HTTP capture uses the `dart:io` HTTP profiler, which is the data source of the
DevTools Network tab. **You do not need to configure Dio or other clients.**

| Client | Captured |
|---|---|
| `dart:io` `HttpClient` | Yes |
| [`dio`](https://pub.dev/packages/dio) with its default adapter | Yes, because it uses `HttpClient` |
| [`http`](https://pub.dev/packages/http) (`http.get`, `IOClient`) | Yes, because it uses `HttpClient` |
| Anything built on the two above (Retrofit, Chopper, GraphQL clients, `Image.network`, …) | Yes |
| [`cupertino_http`](https://pub.dev/packages/cupertino_http), [`cronet_http`](https://pub.dev/packages/cronet_http), [`ok_http`](https://pub.dev/packages/ok_http) | Yes, through [`http_profile`](https://pub.dev/packages/http_profile) |
| Clients that use native code or raw sockets without `http_profile` (for example, `native_dio_adapter`, HTTP/2 adapters, platform-channel clients) | No |
| WebSockets, gRPC | No |

For details, see the
[DevTools Network view documentation](https://docs.flutter.dev/tools/devtools/network).

The profiler records each request with its headers, bodies, status, timing
and errors (for example, a failed DNS lookup or a refused connection). A
request is `completed` when its response has fully arrived or it failed.

**Requests made at startup:** the profiler records requests only after it is
turned on. The server turns it on when it connects, usually one or two
seconds after the app starts. To also capture the first requests, turn it on
yourself in debug builds:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';

void main() {
  if (kDebugMode) HttpClient.enableTimelineLogging = true;
  runApp(const MyApp());
}
```

### Noise filter

HTTP list, search, summary and context tools hide background traffic by
default: Sentry, Google Analytics, Firebase telemetry, `/health`, `/ping` and
`/heartbeat`. Pass `includeNoise: true` to show it. `get_http_request` with an
id always works.

To hide more URLs, put patterns in a file and pass it with `--noise`. The
built-in patterns stay active.

```text
# Substrings of the URL
/metrics
api.segment.io
# A regular expression
regex:^https://cdn\.example\.com/
```

## Buffers and ids

- The server keeps the last **2,000 console entries** and **500 HTTP
  requests**. Older entries are deleted.
- The buffers are in the memory of the server. They do not change the app.
  They are lost when the agent session ends, because the agent stops the
  server.
- The buffers survive hot restarts, full restarts and crashes. When the app is
  not running, tools answer from the buffers with a `warning` field. This lets
  the agent read the last output of an app that crashed.
- Console entries and HTTP requests have separate ids (`"1"`, `"2"`, …). An id
  is not used again while the server runs, also across app restarts.
- Each agent session starts its own server with its own buffers. Many servers
  can connect to the same app at the same time.

## Privacy and security

Everything stays on your computer until the agent reads it. But when a tool
returns logs, headers or bodies, that data goes into the agent's context and
to the model provider.

- `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`
  and `X-Auth-Token` header values are replaced with `<redacted>` by default.
  To turn this off, pass `--no-redact-headers`.
- Request and response **bodies are not redacted**, and neither are logs. If
  your app handles personal or sensitive data, use test accounts and test
  data.
- Logs and response bodies are **untrusted input** for the agent. A server
  response can contain text that looks like instructions. The server tells the
  agent to treat this content as data, but you should still review what the
  agent does after it reads them.
- The VM service URI contains a secret token. Anybody who has the URI can run
  code in your debug app. The URI file in `/tmp` can be read by other users of
  the same computer. On a shared computer, put the file in a private
  directory, both in `flutter run` and in `--uri-file`.
- While the HTTP profiler is on, the app keeps every request and its body in
  memory, the same as when the DevTools Network tab records. This is not a
  problem in normal debug sessions. In a very long session with many large
  downloads, restart the app from time to time.

## Options

```
--uri-file=<path>         File that `flutter run --vmservice-out-file` writes
                          to. Default: /tmp/flutter_peek_vmservice.txt
                          (%TEMP% on Windows). Also: FLUTTER_PEEK_URI_FILE.
--noise=<path>            File with extra URL patterns to hide, one per line.
                          A "regex:" prefix makes a regular expression, and
                          "#" starts a comment.
--[no-]redact-headers     Redact credential headers (default: on).
--version, --help
```

Example: two apps at the same time. Give each project its own URI file, both
in `flutter run` and in that project's `.mcp.json`:

```json
{
  "mcpServers": {
    "flutter-peek": {
      "command": "flutter_peek_mcp",
      "args": ["--uri-file=/tmp/my_app_vmservice.txt"]
    }
  }
}
```

## Limitations

- **Flutter web is not supported.** The browser does not have the `dart:io`
  HTTP profiler. Use the browser DevTools for web.
- **Release builds** have no VM service.
- **Only the main isolate's HTTP traffic is captured.** Requests made in a
  background isolate (for example, in `Isolate.run`) are not. Console output
  from all isolates is captured.
- **WebSockets, gRPC and native HTTP clients** without `http_profile` are not
  captured. See the [client table](#http).
- **Requests made before the server connected** are not captured, unless the
  app turns on the profiler itself. See
  [Requests made at startup](#http).
- **One app per server.** The server connects to the main isolate of one app.
  To watch two apps, use two URI files. See [Options](#options).

## Troubleshooting

**`connected: false`, "No VM service URI file"**: the app was started
without `--vmservice-out-file`, or with a different path than `--uri-file`.
Restart the app with the flag, or ask the agent to `connect` to the URI that
`flutter run` printed.

**`flutter_peek_mcp: command not found` when the agent starts the server**:
agents often start servers without your shell `PATH`. Use the full path of
the executable as the command. To find it, run `which flutter_peek_mcp` in
your terminal.

**No HTTP requests**: check that the client is in the
[client table](#http), that the app runs in debug or profile mode, and that
the requests are made in the main isolate. Requests made before the server
connected are not captured (see
[Requests made at startup](#http)).

**HTTP bodies are empty**: the app is probably paused at a breakpoint.
Resume it. Bodies of images and other binary files show only their size.

**The server log**: the server writes its diagnostics (connections, restarts,
errors) to stderr. MCP clients usually keep this output in their MCP logs.

**Smoke test without an agent**:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"is_app_connected","arguments":{}}}' \
  | flutter_peek_mcp
```

The response to id 2 shows whether the app is connected. If it is not, the
response says why.

## Development

```bash
dart pub get
dart format .
dart analyze
dart test
```

`test/vm_client_test.dart` starts `test/fixtures/sample_app.dart` with the VM
service enabled and checks what the server captures from it. It needs only
the Dart SDK.

Issues and pull requests are welcome.

## License

[MIT](LICENSE)
