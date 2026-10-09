import 'package:flutter/foundation.dart';

import '../log.dart';
import '../models/product.dart';

class CartLine {
  CartLine(this.product, this.quantity);

  final Product product;
  int quantity;

  double get total => product.price * quantity;
}

class Cart extends ChangeNotifier {
  static const _log = Log('Cart');

  final _lines = <CartLine>[];

  /// The lines, sorted by product title.
  List<CartLine> get lines =>
      [..._lines]..sort((a, b) => a.product.title.compareTo(b.product.title));

  int get itemCount => _lines.fold(0, (sum, line) => sum + line.quantity);

  double get total => _lines.fold(0, (sum, line) => sum + line.total);

  void add(Product product) {
    final line = _lines.where((l) => l.product.id == product.id).firstOrNull;
    if (line != null) {
      line.quantity++;
    } else {
      _lines.add(CartLine(product, 1));
    }
    _log.info('Added "${product.title}" (items in the cart: $itemCount)');
    notifyListeners();
  }

  void removeAt(int index) {
    _lines.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
