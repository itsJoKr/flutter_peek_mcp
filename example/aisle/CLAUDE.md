# Aisle

A Flutter shop on top of the [DummyJSON](https://dummyjson.com/docs/products)
API: categories ("aisles"), products, a product page, a bag (the cart) and a
checkout.

## Debugging the running app

When a bug involves the running app, use the flutter-peek MCP tools before you
ask me for logs: start with `http_summary` and
`list_console_logs(level: "error")`, then open entries with the `get_*` tools.

The app logs with `Log` from `lib/log.dart`, which writes through
`dart:developer` `log()`. Use it for the logs you add, so flutter-peek shows
their level, logger name, error and stack trace.

## Running the app

When I ask you to run the app (for example, "run this on my mac"), start it in
debug mode, in the background, and keep it running. Always use this command,
with `--vmservice-out-file`:

```bash
flutter run -d macos --vmservice-out-file=/tmp/flutter_peek_vmservice.txt
```

When that is all I ask, start the app and stop there. Use an iOS simulator or
an Android emulator instead of `macos` if I ask for one.

## Driving the app with marionette

The app starts `MarionetteBinding` in debug mode, and `marionette_cli` is a dev
dependency, so you can tap, type, scroll and take screenshots. Read logs with
flutter-peek, not with `marionette get-logs`.

Register the running app once, and again after every new `flutter run`. The
URI file holds the `ws://…/ws` URI that marionette needs:

```bash
dart run marionette_cli:marionette register aisle "$(cat /tmp/flutter_peek_vmservice.txt)"
```

Then:

```bash
dart run marionette_cli:marionette -i aisle get-interactive-elements
dart run marionette_cli:marionette -i aisle tap --key category_beauty
dart run marionette_cli:marionette -i aisle press-back-button
dart run marionette_cli:marionette -i aisle take-screenshots --output /tmp/aisle.png
dart run marionette_cli:marionette -i aisle hot-reload
```

Hot reload after you change the code. `dart run marionette_cli:marionette help-ai`
prints the full reference.

The widgets that you tap have keys:

- Home: `category_<slug>`, `featured_fragrances`, `cart_button`
- Products: `product_<id>`, `add_<id>` (the quick add button on a product card)
- Product page: `add_to_cart`
- Bag: `cart_line_<id>`, `remove_<id>`, `checkout_button`, `order_placed_ok`,
  `start_shopping`
- Errors: `retry_button`
