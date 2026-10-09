import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cart/cart.dart';
import '../models/category.dart';
import '../models/order.dart';
import '../models/product.dart';

/// Client for the DummyJSON shop API (https://dummyjson.com/docs/products).
class ShopApi {
  ShopApi({http.Client? client}) : _client = client ?? http.Client();

  static const _host = 'dummyjson.com';

  /// DummyJSON has no login here, so every order goes to its first user.
  static const _userId = 1;

  final http.Client _client;

  Future<List<Category>> categories() async {
    final json = await _get('/products/categories') as List<dynamic>;
    return [
      for (final category in json)
        Category.fromJson(category as Map<String, dynamic>),
    ];
  }

  Future<List<Product>> productsInCategory(String slug) async {
    final json = await _get('/products/category/$slug') as Map<String, dynamic>;
    return [
      for (final product in json['products'] as List<dynamic>)
        Product.fromJson(product as Map<String, dynamic>),
    ];
  }

  Future<Order> checkout(List<CartLine> lines) async {
    final body = {
      'userId': _userId,
      'products': [
        for (final line in lines)
          {'id': line.product.id, 'quantity': line.quantity},
      ],
    };
    final json = await _post('/carts/add', body) as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<Object?> _get(String path) async {
    final response = await _client.get(Uri.https(_host, path));
    return _decode(response);
  }

  Future<Object?> _post(String path, Object body) async {
    final response = await _client.post(
      Uri.https(_host, path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Object? _decode(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, response.request?.url);
    }
    return jsonDecode(response.body);
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.url);

  final int statusCode;
  final Uri? url;

  @override
  String toString() => 'ApiException: HTTP $statusCode from $url';
}
