import 'package:flutter/material.dart';

import '../app.dart';
import '../cart/cart.dart';
import '../format.dart';
import '../log.dart';
import '../models/order.dart';
import '../theme.dart';
import '../widgets/product_image.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const _log = Log('CartScreen');

  bool _checkingOut = false;

  Future<void> _checkout(Cart cart) async {
    setState(() => _checkingOut = true);
    try {
      final order = await ShopScope.of(context).api.checkout(cart.lines);
      _log.info(
        'Placed order ${order.id}: ${formatItems(order.totalQuantity)}, '
        '${formatPrice(order.total)}',
      );
      cart.clear();
      if (mounted) await _showOrderPlaced(order);
    } catch (error, stackTrace) {
      _log.error('Checkout failed', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checkout failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _showOrderPlaced(Order order) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _OrderPlacedDialog(order: order),
    );
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ShopScope.of(context).cart;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final lines = cart.lines;
        return Scaffold(
          appBar: AppBar(title: const Text('Your bag')),
          body: lines.isEmpty
              ? const _EmptyCart()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _CartLineCard(
                    line: lines[index],
                    color: AisleColors.pastel(index),
                    onRemove: () => cart.removeAt(index),
                  ),
                ),
          bottomNavigationBar: lines.isEmpty
              ? null
              : _CheckoutPanel(
                  cart: cart,
                  checkingOut: _checkingOut,
                  onCheckout: () => _checkout(cart),
                ),
        );
      },
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.line,
    required this.color,
    required this.onRemove,
  });

  final CartLine line;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = line.product;
    return Container(
      key: ValueKey('cart_line_${product.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AisleColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 76,
            child: ProductImage(product.thumbnail, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: AisleColors.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '${line.quantity} × ${formatPrice(product.price)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AisleColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                key: ValueKey('remove_${product.id}'),
                tooltip: 'Remove',
                style: IconButton.styleFrom(backgroundColor: AisleColors.cream),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: onRemove,
              ),
              const SizedBox(height: 4),
              Text(formatPrice(line.total), style: textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutPanel extends StatelessWidget {
  const _CheckoutPanel({
    required this.cart,
    required this.checkingOut,
    required this.onCheckout,
  });

  final Cart cart;
  final bool checkingOut;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyLarge?.copyWith(color: AisleColors.muted);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AisleColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Subtotal', style: muted)),
                  Text(formatPrice(cart.total), style: muted),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text('Delivery', style: muted)),
                  Text(
                    'Free',
                    style: muted?.copyWith(
                      color: AisleColors.forest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(),
              ),
              Row(
                children: [
                  Expanded(child: Text('Total', style: textTheme.titleLarge)),
                  Text(
                    formatPrice(cart.total),
                    key: const ValueKey('cart_total'),
                    style: textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('checkout_button'),
                  onPressed: checkingOut ? null : onCheckout,
                  child: Text(
                    checkingOut
                        ? 'Placing your order…'
                        : 'Checkout · ${formatItems(cart.itemCount)}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AisleColors.pastel(2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 52,
                color: AisleColors.forest,
              ),
            ),
            const SizedBox(height: 24),
            Text('Your bag is empty', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Find something you love.',
              style: textTheme.bodyLarge?.copyWith(color: AisleColors.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('start_shopping'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32),
              ),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Start shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPlacedDialog extends StatelessWidget {
  const _OrderPlacedDialog({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: AisleColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AisleColors.pastel(1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 44,
                color: AisleColors.forest,
              ),
            ),
            const SizedBox(height: 20),
            Text('Order placed!', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Order #${order.id} · ${formatItems(order.totalQuantity)} · '
              '${formatPrice(order.total)}',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: AisleColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              'Thanks for shopping with Aisle.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: AisleColors.muted),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('order_placed_ok'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep shopping'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
