# Aisle

*Good things, one aisle away.*

Aisle is a small Flutter shop for trying flutter-peek with an AI agent. It
sells the catalog of the free [DummyJSON](https://dummyjson.com/docs/products)
API: you browse the aisles, open a product, put it in your bag and check out.

The app has two bugs on purpose. Each one is a demo:

1. **An error that you see.** The agent finds out what went wrong from the
   console and the HTTP traffic, without you copying logs.
2. **A bug report without an error.** The agent adds logs, runs the app,
   reproduces the bug with [marionette](https://pub.dev/packages/marionette_cli),
   and reads its own logs with flutter-peek.

The app is set up for both tools:

- `lib/main.dart` turns on the HTTP profiler at startup, so flutter-peek also
  sees the first requests, and starts `MarionetteBinding` in debug mode.
- `lib/log.dart` logs through `dart:developer` `log()`, so flutter-peek gets
  levels, logger names and stack traces.
- `marionette_cli` is a dev dependency, so the agent drives the app with
  `dart run marionette_cli:marionette`, at the same version as the app's
  `marionette_flutter`.
- [`.mcp.json`](.mcp.json) starts flutter-peek from this checkout.
- [`CLAUDE.md`](CLAUDE.md) tells the agent how to use flutter-peek, how to run
  the app, and how to drive it with marionette.

## Setup

```bash
# The flutter-peek server, from this checkout
dart pub get

# The app
cd example/aisle
flutter pub get
```

Start Claude Code in `example/aisle`, accept the `flutter-peek` server from
`.mcp.json`, and check with `/mcp` that it is connected.

The demos use macOS, because it needs no simulator. The app opens in a
phone-sized window. iOS and Android work too.

## Demo 1: "I see an error. What happened?"

Run the app yourself:

```bash
flutter run -d macos --vmservice-out-file=/tmp/flutter_peek_vmservice.txt
```

Open the **Groceries** aisle. The app says "Couldn't load the products. Check
your connection and try again." Ask the agent:

```text
I opened Groceries in the app and I see an error: "Couldn't load the products."
What happened there?
```

The agent reads the error and its stack trace in the console, then opens the
response of the request that the app was reading, and explains the cause. The
app blames the connection, but the HTTP traffic shows that the request worked.

## Demo 2: a bug report

In this demo the agent runs the app. Stop your `flutter run` first, or leave
it running and the agent uses it. Give the agent the bug report:

```text
QA filed this bug, and I don't know the cause yet:

  SHOP-142: Removing an item from the bag sometimes removes a different item

  Steps:
  1. Add a few products to the bag.
  2. Open the bag.
  3. Tap the trash icon next to one of the products.

  Expected: the product that I tapped is removed.
  Actual: sometimes a different product disappears, and the one that I tapped
  stays in the bag. It does not happen every time. I saw it with products
  from Beauty.

Find the cause. Add logs where they help, run the app, reproduce the bug with
marionette, and read the logs with flutter-peek. When you know the cause, fix
it and check the fix in the running app.
```

The agent adds `Log` calls, starts the app, registers it with marionette, and
taps through the steps: an aisle, a few products, the bag, a trash icon. It
reads its logs with flutter-peek to see what the app did, finds the pattern
behind "sometimes", fixes the code, hot reloads, and repeats the steps to
check the fix.

## Run a demo again

The agent changes the code. To put the bugs back:

```bash
git restore lib/
```

## Use the installed server

In your own projects, install the server and use its command instead of the
checkout:

```bash
dart install flutter_peek_mcp
```

```json
{
  "mcpServers": {
    "flutter-peek": {
      "command": "flutter_peek_mcp"
    }
  }
}
```
