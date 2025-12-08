import 'cart_item.dart';
import 'geo_point.dart';

enum OrderStatus { processing, flying, delivered }

class Order {
  final String id;
  final List<CartItem> items;
  final double totalWeight;
  final GeoPoint destination;
  final OrderStatus status;

  const Order({
    required this.id,
    required this.items,
    required this.totalWeight,
    required this.destination,
    required this.status,
  });

  Order copyWith({
    List<CartItem>? items,
    double? totalWeight,
    GeoPoint? destination,
    OrderStatus? status,
  }) {
    return Order(
      id: id,
      items: items ?? this.items,
      totalWeight: totalWeight ?? this.totalWeight,
      destination: destination ?? this.destination,
      status: status ?? this.status,
    );
  }
}
