import 'package:flutter/material.dart';

import '../app.dart';
import '../format.dart';
import '../log.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../theme.dart';
import '../widgets/cart_button.dart';
import '../widgets/error_view.dart';
import '../widgets/product_image.dart';
import 'product_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    required this.category,
    required this.color,
  });

  final Category category;

  /// The background of the product photos, from the category's tile.
  final Color color;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _log = Log('ProductsScreen');

  late Future<List<Product>> _products = _load();

  Future<List<Product>> _load() async {
    final slug = widget.category.slug;
    try {
      final products = await ShopScope.of(context).api.productsInCategory(slug);
      _log.info('Loaded ${products.length} products in "$slug"');
      return products;
    } catch (error, stackTrace) {
      _log.error('Could not load the products in "$slug"', error, stackTrace);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(pinned: true, actions: [CartButton()]),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            sliver: SliverToBoxAdapter(
              child: Text(widget.category.name, style: textTheme.headlineLarge),
            ),
          ),
          FutureBuilder(
            future: _products,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorView(
                    message: "Couldn't load the products.",
                    onRetry: () => setState(() => _products = _load()),
                  ),
                );
              }
              final products = snapshot.data;
              if (products == null) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.6,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) => _ProductCard(
                    product: products[index],
                    color: widget.color,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.color});

  final Product product;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AisleColors.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('product_${product.id}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductScreen(product: product, color: color),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ProductImage(product.thumbnail, color: color),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.brand.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: AisleColors.muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AisleColors.saffron,
                    ),
                    Text(
                      product.rating.toStringAsFixed(1),
                      style: textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      formatPrice(product.price),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    key: ValueKey('add_${product.id}'),
                    tooltip: 'Add to cart',
                    onPressed: product.stock > 0
                        ? () => addToCart(context, product)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
