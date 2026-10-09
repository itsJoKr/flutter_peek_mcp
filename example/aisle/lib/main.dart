import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'api/shop_api.dart';
import 'app.dart';
import 'cart/cart.dart';

void main() {
  if (kDebugMode) {
    // Lets an agent drive the app with marionette: tap, type, screenshot.
    MarionetteBinding.ensureInitialized();
    // Records HTTP traffic from the first request, so flutter-peek also sees
    // the requests made before it connected.
    HttpClient.enableTimelineLogging = true;
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(AisleApp(api: ShopApi(), cart: Cart()));
}
