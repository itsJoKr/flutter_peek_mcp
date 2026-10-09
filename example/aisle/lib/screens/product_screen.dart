import 'package:flutter/material.dart';

import '../format.dart';
import '../models/product.dart';
import '../theme.dart';
import '../widgets/cart_button.dart';

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.product, required this.color});

  final Product product;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rating = product.rating.toStringAsFixed(1);
    final reviews = product.reviews.length;
    return Scaffold(
      appBar: AppBar(backgroundColor: color, actions: const [CartButton()]),
      body: ListView(
        children: [
          Container(
            height: 300,
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(36),
              ),
            ),
            child: Image.network(
              product.images.firstOrNull ?? product.thumbnail,
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand.toUpperCase(),
                  style: textTheme.labelLarge?.copyWith(
                    color: AisleColors.forest,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(product.title, style: textTheme.headlineMedium),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      icon: Icons.star_rounded,
                      iconColor: AisleColors.saffron,
                      label: '$rating · $reviews reviews',
                      color: AisleColors.card,
                    ),
                    _StockPill(product: product),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  product.description,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AisleColors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _InfoCard(
                  rows: [
                    (
                      Icons.local_shipping_outlined,
                      product.shippingInformation,
                    ),
                    (Icons.verified_outlined, product.warrantyInformation),
                    (Icons.assignment_return_outlined, product.returnPolicy),
                  ],
                ),
                const SizedBox(height: 28),
                Text('What people say', style: textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final (index, review) in product.reviews.indexed)
                  _ReviewCard(review: review, color: AisleColors.pastel(index)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AddToCartBar(product: product),
    );
  }
}

class _AddToCartBar extends StatelessWidget {
  const _AddToCartBar({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final inStock = product.stock > 0;
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
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Price',
                    style: textTheme.labelMedium?.copyWith(
                      color: AisleColors.muted,
                    ),
                  ),
                  Text(
                    formatPrice(product.price),
                    style: textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('add_to_cart'),
                  onPressed: inStock ? () => addToCart(context, product) : null,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(inStock ? 'Add to cart' : 'Out of stock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final (color, iconColor) = switch (product.availabilityStatus) {
      'In Stock' => (AisleColors.pastel(1), AisleColors.forest),
      'Low Stock' => (AisleColors.pastel(2), const Color(0xFF9A6B00)),
      _ => (AisleColors.pastel(5), const Color(0xFFB3261E)),
    };
    final label = product.stock > 0
        ? '${product.availabilityStatus} · ${product.stock} left'
        : product.availabilityStatus;
    return _Pill(
      icon: Icons.inventory_2_outlined,
      iconColor: iconColor,
      label: label,
      color: color,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<(IconData, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AisleColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final (index, (icon, text)) in rows.indexed) ...[
            if (index > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: AisleColors.forest),
                  const SizedBox(width: 14),
                  Expanded(child: Text(text)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.color});

  final Review review;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final initials = review.reviewerName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AisleColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color,
            foregroundColor: AisleColors.ink,
            child: Text(initials, style: textTheme.titleSmall),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.reviewerName,
                        style: textTheme.titleSmall,
                      ),
                    ),
                    for (var star = 1; star <= 5; star++)
                      Icon(
                        star <= review.rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: AisleColors.saffron,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  review.comment,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AisleColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
