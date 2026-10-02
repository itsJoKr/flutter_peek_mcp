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

## How it works

```
 Flutter app (debug/profile)                         AI agent
 ┌──────────────────────────┐   VM service     ┌─────────────────┐
 │ print / debugPrint       │──── Stdout ────┐ │                 │
 │ dart:developer log()     │──── Logging ───┤ │  Claude Code,   │
 │ dart:io HttpClient       │                ├─│  Cursor, …      │
 │  (Dio, package:http, …)  │── HTTP profile ┘ │                 │
 └──────────────────────────┘        ▲         └────────▲────────┘
                                     │  flutter_peek_mcp │ stdio (MCP)
                                     └───────────────────┘
```

- **Console**: the server subscribes to the VM service `Stdout`, `Stderr` and
  `Logging` streams. DDS (started by `flutter run`) replays its buffered
  events to new clients, so you also get output from before the server
  connected.
- **HTTP**: the server turns on the `dart:io` HTTP profiler
  (`HttpClient.enableTimelineLogging`), the same as the DevTools Network tab.
  Then it polls the profile every 1.5 s. See
  [Which HTTP clients are captured](#which-http-clients-are-captured).
- **Buffers**: the last 2,000 console lines and 500 HTTP requests are kept in
  memory. They stay available after the app stops or crashes, so the agent
  can still look at what happened.

## Requirements

- Dart SDK 3.5 or later (included with Flutter 3.24 or later).
- The app must run in **debug** or **profile** mode. Release builds have no VM
  service.
- Android, iOS, macOS, Windows and Linux. Flutter web is not supported,
  because the browser does not have the `dart:io` HTTP profiler.

## Setup

### 1. Install

```bash
dart pub global activate --source git https://github.com/itsJoKr/flutter_peek_mcp
```

This installs the `flutter_peek_mcp` executable in `~/.pub-cache/bin`. Make
sure that directory is on your `PATH`. If you use FVM, run
`fvm dart pub global activate …` instead.

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

That is all. The server finds the app automatically and connects again after a
hot restart or a full restart.

**No flag?** If the app is already running, ask the agent to connect to the VM
service URI. `flutter run` prints it as
`A Dart VM Service on … is available at: http://127.0.0.1:PORT/TOKEN=/`. The
agent calls the `connect` tool with that URI. A DevTools URL also works.

## Tools

| Tool | Purpose |
|---|---|
| `is_app_connected` | Connection status, buffer sizes and setup hints. |
| `connect(uri?)` | Connect to a VM service URI. With no URI, use the URI file again. |
| `list_http_requests` | Scan requests. Shows metadata only (method, URL, status, duration, sizes). |
| `get_http_request(id)` | One request with full headers and bodies. |
| `get_http_requests_with_bodies` | Up to 10 requests with bodies. A filter is required. |
| `search_http_requests(query)` | Find text in URLs, headers or bodies. |
| `http_summary` | Counts by status and method, error rate, slowest and most frequent URLs. |
| `list_console_logs` | Scan console output. Filter by text, regex, level, source or time. |
| `get_console_log(id)` | Full text of one entry, with the entries around it. |
| `search_console_logs(query)` | grep-style search with context. |
| `get_context_around` | Logs and HTTP requests in time order, around a timestamp, log or request. |
| `clear_buffers` | Start clean before you reproduce a bug. |

Design choices:

- **Bodies only on request.** List and search tools return metadata and short
  snippets. Bodies come only from `get_*` tools, and the bulk tool requires a
  filter. This keeps the agent's context small.
- **Responses stay small.** `get_http_request` returns up to 20,000
  characters of each body. You can read the rest with `bodyOffset`. The bulk
  tool returns 2,000 characters for each body. A complete JSON body is
  returned as JSON, not as an escaped string. Binary bodies are shown as a
  byte count.
- **Images and other binary downloads are not prefetched.** Their bodies
  (and all bodies larger than 1 MB) are fetched only when a tool asks for
  them. This keeps apps with many `Image.network` calls fast.
- **Breakpoints do not block the agent.** While the app is paused in the
  debugger, tools still answer from the buffers. Bodies that were not fetched
  yet stay empty until the app runs again.
- **Background traffic is hidden** from HTTP tools by default: Sentry, Google
  Analytics, Firebase telemetry, `/health`, `/ping`, and similar. Pass
  `includeNoise: true` to show it, or add your own patterns with `--noise`.

## Which HTTP clients are captured

HTTP capture uses the `dart:io` HTTP profiler, which is the data source of the
DevTools Network tab. **You do not need to configure Dio or other clients.**

| Client | Captured |
|---|---|
| `dart:io` `HttpClient` | Yes |
| [`dio`](https://pub.dev/packages/dio) with its default adapter | Yes, because it uses `HttpClient` |
| [`http`](https://pub.dev/packages/http) (`http.get`, `IOClient`) | Yes, because it uses `HttpClient` |
| Anything built on the two above (Retrofit, Chopper, GraphQL clients, …) | Yes |
| [`cupertino_http`](https://pub.dev/packages/cupertino_http), [`cronet_http`](https://pub.dev/packages/cronet_http), [`ok_http`](https://pub.dev/packages/ok_http) | Yes, through [`http_profile`](https://pub.dev/packages/http_profile) |
| Clients that use native code or raw sockets without `http_profile` (for example, `native_dio_adapter`, HTTP/2 adapters, platform-channel clients) | No |
| WebSockets, gRPC | No |
| Flutter web | No |

For details, see the
[DevTools Network view documentation](https://docs.flutter.dev/tools/devtools/network).

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

## Privacy

Everything stays on your computer until the agent reads it. But when a tool
returns logs, headers or bodies, that data goes into the agent's context and
to the model provider. Keep this in mind:

- `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`
  and `X-Auth-Token` header values are replaced with `<redacted>` by default.
  To turn this off, pass `--no-redact-headers`.
- Request and response **bodies are not redacted**. If your app handles
  personal or sensitive data, use test accounts and test data.
- Logs and response bodies are **untrusted input** for the agent. A server
  response can contain text that looks like instructions. The server tells the
  agent to treat this content as data, but you should still review what the
  agent does after it reads them.

While the HTTP profiler is on, the app keeps every request and its body in
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

## Troubleshooting

**`connected: false`, "No VM service URI file"**: the app was started
without `--vmservice-out-file`, or with a different path than `--uri-file`.
Restart the app with the flag, or ask the agent to `connect` to the URI that
`flutter run` printed.

**`flutter_peek_mcp: command not found` when the agent starts the server**:
agents often start servers without your shell `PATH`. Use the full path
(`~/.pub-cache/bin/flutter_peek_mcp`) as the command.

**No HTTP requests**: check that the client is in the
[table above](#which-http-clients-are-captured), and that the app runs in
debug or profile mode. Requests made before the server connected are not
captured (see the startup tip above).

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

## License

[MIT](LICENSE)
