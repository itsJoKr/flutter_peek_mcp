/// An order, as `POST /carts/add` returns it.
class Order {
  const Order({
    required this.id,
    required this.total,
    required this.totalQuantity,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as int,
      total: (json['total'] as num).toDouble(),
      totalQuantity: json['totalQuantity'] as int,
    );
  }

  final int id;
  final double total;
  final int totalQuantity;
}
