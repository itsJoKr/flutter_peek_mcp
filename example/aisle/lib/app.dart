import 'package:flutter/material.dart';

import 'api/shop_api.dart';
import 'cart/cart.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

class AisleApp extends StatelessWidget {
  const AisleApp({super.key, required this.api, required this.cart});

  final ShopApi api;
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return ShopScope(
      api: api,
      cart: cart,
      child: MaterialApp(
        title: 'Aisle',
        debugShowCheckedModeBanner: false,
        theme: buildAisleTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}

/// Gives the screens access to the API and the cart.
class ShopScope extends InheritedWidget {
  const ShopScope({
    super.key,
    required this.api,
    required this.cart,
    required super.child,
  });

  final ShopApi api;
  final Cart cart;

  static ShopScope of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShopScope>()!;

  // main() creates the API and the cart once, so they never change.
  @override
  bool updateShouldNotify(ShopScope oldWidget) => false;
}
