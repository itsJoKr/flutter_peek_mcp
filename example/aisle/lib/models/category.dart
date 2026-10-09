class Category {
  const Category({required this.slug, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(slug: json['slug'] as String, name: json['name'] as String);
  }

  final String slug;
  final String name;

  /// A product photo that stands for the category on the home screen.
  String? get coverUrl {
    final product = _coverProducts[slug];
    if (product == null) return null;
    return 'https://cdn.dummyjson.com/product-images/$slug/$product/thumbnail.webp';
  }

  static const _coverProducts = {
    'beauty': 'red-lipstick',
    'fragrances': 'gucci-bloom-eau-de',
    'furniture': 'annibale-colombo-sofa',
    'groceries': 'apple',
    'home-decoration': 'table-lamp',
    'kitchen-accessories': 'boxed-blender',
    'laptops': 'apple-macbook-pro-14-inch-space-grey',
    'mens-shirts': 'man-plaid-shirt',
    'mens-shoes': 'nike-air-jordan-1-red-and-black',
    'mens-watches': 'rolex-submariner-watch',
    'mobile-accessories': 'apple-airpods-max-silver',
    'motorcycle': 'kawasaki-z800',
    'skin-care': 'olay-ultra-moisture-shea-butter-body-wash',
    'smartphones': 'iphone-13-pro',
    'sports-accessories': 'basketball',
    'sunglasses': 'classic-sun-glasses',
    'tablets': 'ipad-mini-2021-starlight',
    'tops': 'girl-summer-dress',
    'vehicle': 'charger-sxt-rwd',
    'womens-bags': 'prada-women-bag',
    'womens-dresses': 'dress-pea',
    'womens-jewellery': 'green-crystal-earring',
    'womens-shoes': 'calvin-klein-heel-shoes',
    'womens-watches': 'watch-gold-for-women',
  };
}
