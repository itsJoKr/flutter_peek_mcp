class Product {
  const Product({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.brand,
    required this.price,
    required this.rating,
    required this.stock,
    required this.availabilityStatus,
    required this.shippingInformation,
    required this.warrantyInformation,
    required this.returnPolicy,
    required this.thumbnail,
    required this.images,
    required this.reviews,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      brand: json['brand'] as String,
      price: (json['price'] as num).toDouble(),
      rating: (json['rating'] as num).toDouble(),
      stock: json['stock'] as int,
      availabilityStatus: json['availabilityStatus'] as String,
      shippingInformation: json['shippingInformation'] as String,
      warrantyInformation: json['warrantyInformation'] as String,
      returnPolicy: json['returnPolicy'] as String,
      thumbnail: json['thumbnail'] as String,
      images: (json['images'] as List<dynamic>).cast<String>(),
      reviews: [
        for (final review in json['reviews'] as List<dynamic>)
          Review.fromJson(review as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final String title;
  final String description;
  final String category;
  final String brand;
  final double price;
  final double rating;
  final int stock;

  /// "In Stock", "Low Stock" or "Out of Stock".
  final String availabilityStatus;
  final String shippingInformation;
  final String warrantyInformation;
  final String returnPolicy;
  final String thumbnail;
  final List<String> images;
  final List<Review> reviews;
}

class Review {
  const Review({
    required this.rating,
    required this.comment,
    required this.reviewerName,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      rating: json['rating'] as int,
      comment: json['comment'] as String,
      reviewerName: json['reviewerName'] as String,
    );
  }

  final int rating;
  final String comment;
  final String reviewerName;
}
