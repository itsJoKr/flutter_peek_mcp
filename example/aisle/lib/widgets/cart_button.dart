import 'package:flutter/material.dart';

import '../app.dart';
import '../models/product.dart';
import '../screens/cart_screen.dart';
import '../theme.dart';

/// App bar button that opens the cart and shows how many items it holds.
class CartButton extends StatelessWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = ShopScope.of(context).cart;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ListenableBuilder(
        listenable: cart,
        builder: (context, _) => IconButton(
          key: const ValueKey('cart_button'),
          tooltip: 'Cart',
          style: IconButton.styleFrom(
            backgroundColor: AisleColors.card,
            foregroundColor: AisleColors.ink,
          ),
          icon: Badge(
            label: Text('${cart.itemCount}'),
            isLabelVisible: cart.itemCount > 0,
            child: const Icon(Icons.shopping_bag_outlined),
          ),
          onPressed: () => openCart(context),
        ),
      ),
    );
  }
}

void openCart(BuildContext context) {
  // An "Added to cart" message would cover the checkout button.
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const CartScreen()));
}

/// Adds [product] to the cart and confirms it with a message.
void addToCart(BuildContext context, Product product) {
  ShopScope.of(context).cart.add(product);
  // The message can outlive this screen, so it must not use its context.
  final navigator = Navigator.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AisleColors.saffron),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${product.title} is in your bag',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => navigator.push(
            MaterialPageRoute<void>(builder: (_) => const CartScreen()),
          ),
        ),
      ),
    );
}
