import 'package:flutter/material.dart';

import '../theme.dart';

/// A product photo on a soft colored background. It fills its parent.
class ProductImage extends StatelessWidget {
  const ProductImage(
    this.url, {
    super.key,
    required this.color,
    this.radius = 16,
    this.padding = const EdgeInsets.all(10),
  });

  final String url;
  final Color color;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(
        padding: padding,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.image_outlined, color: AisleColors.muted),
          ),
        ),
      ),
    );
  }
}
