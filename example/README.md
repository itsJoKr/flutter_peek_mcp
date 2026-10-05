# Example: use flutter-peek with Claude Code

flutter_peek_mcp is a command-line MCP server, so the example is a setup, not
Dart code.

## 1. Install the server

```bash
dart install flutter_peek_mcp
```

## 2. Register it in your Flutter project

Put this `.mcp.json` file at the root of the project:

```json
{
  "mcpServers": {
    "flutter-peek": {
      "command": "flutter_peek_mcp"
    }
  }
}
```

## 3. Run the app

```bash
flutter run --vmservice-out-file=/tmp/flutter_peek_vmservice.txt
```

## 4. Ask the agent

```text
> Clear the flutter-peek buffers. I will reproduce the checkout bug now.

  (you reproduce the bug in the app)

> What went wrong?
```

The agent calls `http_summary`, finds a `500` from `POST /api/checkout`,
opens it with `get_http_request`, and reads the error in the response body.
Then it calls `get_context_around` with that request id to see the logs from
the same moment.

See the [README](https://github.com/itsJoKr/flutter_peek_mcp#readme) for all
tools and options.
