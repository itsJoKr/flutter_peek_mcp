String formatPrice(double price) => '\$${price.toStringAsFixed(2)}';

String formatItems(int count) => count == 1 ? '1 item' : '$count items';
