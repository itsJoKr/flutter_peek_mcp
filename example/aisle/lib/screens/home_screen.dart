import 'package:flutter/material.dart';

import '../app.dart';
import '../log.dart';
import '../models/category.dart';
import '../theme.dart';
import '../widgets/cart_button.dart';
import '../widgets/error_view.dart';
import 'products_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _log = Log('HomeScreen');

  late Future<List<Category>> _categories = _load();

  Future<List<Category>> _load() async {
    try {
      final categories = await ShopScope.of(context).api.categories();
      _log.info('Loaded ${categories.length} categories');
      return categories;
    } catch (error, stackTrace) {
      _log.error('Could not load the categories', error, stackTrace);
      rethrow;
    }
  }

  void _openCategory(Category category, Color color) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductsScreen(category: category, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            title: _Wordmark(),
            actions: [CartButton()],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverList.list(
              children: [
                Text(
                  'Good things,\none aisle away.',
                  style: textTheme.headlineLarge,
                ),
                const SizedBox(height: 20),
                _FeaturedBanner(
                  onTap: () => _openCategory(
                    const Category(slug: 'fragrances', name: 'Fragrances'),
                    AisleColors.pastel(3),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Shop by aisle', style: textTheme.titleLarge),
                const SizedBox(height: 12),
              ],
            ),
          ),
          FutureBuilder(
            future: _categories,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: ErrorView(
                    message: "Couldn't load the aisles.",
                    onRetry: () => setState(() => _categories = _load()),
                  ),
                );
              }
              final categories = snapshot.data;
              if (categories == null) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final color = AisleColors.pastel(index);
                    return _CategoryTile(
                      category: category,
                      color: color,
                      onTap: () => _openCategory(category, color),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AisleColors.forest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.shopping_basket_rounded,
            color: AisleColors.cream,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Text.rich(
          TextSpan(
            text: 'aisle',
            children: [
              TextSpan(
                text: '.',
                style: TextStyle(color: AisleColors.saffron),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
      ],
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AisleColors.forest,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('featured_fragrances'),
        onTap: onTap,
        child: SizedBox(
          height: 168,
          child: Stack(
            children: [
              Positioned(
                right: -36,
                bottom: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: AisleColors.saffron.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 8,
                bottom: -4,
                width: 170,
                child: Image.network(
                  'https://cdn.dummyjson.com/product-images/fragrances/'
                  'chanel-coco-noir-eau-de/thumbnail.webp',
                  fit: BoxFit.contain,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AisleColors.cream.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'NEW SEASON',
                        style: textTheme.labelSmall?.copyWith(
                          color: AisleColors.cream,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Signature\nscents',
                      style: textTheme.headlineSmall?.copyWith(
                        color: AisleColors.cream,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Shop fragrances →',
                      style: textTheme.labelLarge?.copyWith(
                        color: AisleColors.cream.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.color,
    required this.onTap,
  });

  final Category category;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final coverUrl = category.coverUrl;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('category_${category.slug}'),
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              width: 140,
              height: 140,
              child: coverUrl == null
                  ? const Icon(Icons.storefront_outlined, size: 56)
                  : Image.network(coverUrl, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                category.name,
                maxLines: 2,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
