import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/cart_item.dart';
import '../models/geo_point.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/store.dart';

class AppState extends ChangeNotifier {
  static const double maxDroneCapacity = 3000; // grams
  static const LatLng fallbackClient = LatLng(43.2409, 76.9170);
  static const String backendBaseUrl = 'http://127.0.0.1:8000';

  final Map<String, CartItem> _cart = {};
  final Map<String, List<Product>> _productsByStore = {};
  List<Store> _stores = [];
  Store? _selectedStore;
  LatLng _deliveryPoint = fallbackClient;
  String _deliveryAddress = '';

  Order? _activeOrder;
  List<LatLng> _flightPath = const [];
  int _droneIndex = 0;
  Timer? _flightTimer;
  bool _useBackendTracking = false;
  LatLng? _backendDronePosition;
  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;
    await _fetchStores();
    if (_stores.isNotEmpty) {
      _selectedStore = _stores.first;
      _deliveryPoint = LatLng(_selectedStore!.latitude + 0.01, _selectedStore!.longitude + 0.01);
      _deliveryAddress = '';
      await _prefetchAllProducts();
    }
    _isInit = true;
    notifyListeners();
  }

  List<Store> get stores => _stores;
  Store? get selectedStore => _selectedStore;
  LatLng get deliveryPoint => _deliveryPoint;

  List<Product> productsForStore(String storeId) => _productsByStore[storeId] ?? const [];

  List<CartItem> get cartItems => _cart.values.toList();
  double get totalPrice => _cart.values.fold(0, (sum, item) => sum + item.totalPrice);
  double get totalWeight => _cart.values.fold(0, (sum, item) => sum + item.totalWeight);
  bool get isOverweight => totalWeight > maxDroneCapacity;
  bool get isCartEmpty => _cart.isEmpty;

  Order? get activeOrder => _activeOrder;
  OrderStatus? get orderStatus => _activeOrder?.status;
  bool get isDelivered => _activeOrder?.status == OrderStatus.delivered;
  String get qrPayload => _activeOrder == null ? '' : 'ORDER_${_activeOrder!.id}_SECRET_KEY';

  List<LatLng> get flightPath => _flightPath;
  LatLng get dronePosition {
    if (_useBackendTracking && _backendDronePosition != null) return _backendDronePosition!;
    if (_activeOrder?.status == OrderStatus.delivered) {
      if (_flightPath.isNotEmpty) return _flightPath.last;
      return _deliveryPoint;
    }
    if (_flightPath.isEmpty) {
      return _selectedStore == null
          ? fallbackClient
          : LatLng(_selectedStore!.latitude, _selectedStore!.longitude);
    }
    return _flightPath[_droneIndex.clamp(0, _flightPath.length - 1)];
  }

  String get statusLabel {
    switch (_activeOrder?.status) {
      case OrderStatus.processing:
        return 'Статус: оплата получена, готовим дрон';
      case OrderStatus.flying:
        if (_useBackendTracking) return 'Дрон в пути (backend)';
        final progress = _flightPath.isEmpty
            ? 0
            : ((_droneIndex / (_flightPath.length - 1)) * 100).clamp(0, 100).round();
        return 'Дрон в пути · $progress%';
      case OrderStatus.delivered:
        return 'Дрон прибыл · покажите QR';
      default:
        return 'Статус: нет активного заказа';
    }
  }

  String get deliveryLabel =>
      '${_deliveryPoint.latitude.toStringAsFixed(5)}, ${_deliveryPoint.longitude.toStringAsFixed(5)}';
  String get deliveryAddress => _deliveryAddress.isNotEmpty ? _deliveryAddress : deliveryLabel;

  Future<void> _fetchStores() async {
    try {
      final resp = await http.get(Uri.parse('$backendBaseUrl/stores'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        _stores = data
            .map((e) => Store(
                  id: e['id'] as String,
                  name: e['name'] as String,
                  address: e['address'] as String,
                  latitude: (e['latitude'] as num).toDouble(),
                  longitude: (e['longitude'] as num).toDouble(),
                ))
            .toList();
      }
    } catch (_) {
      _stores = _fallbackStores;
    }
  }

  Future<void> _fetchProductsForStore(String storeId) async {
    try {
      final resp = await http.get(Uri.parse('$backendBaseUrl/products?store_id=$storeId'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        _productsByStore[storeId] = data
            .map((e) => Product(
                  id: e['id'] as String,
                  storeId: e['storeId'] as String,
                  title: e['title'] as String,
                  price: (e['price'] as num).toDouble(),
                  weight: (e['weight'] as num).toDouble(),
                  imageUrl: e['imageUrl'] as String,
                ))
            .toList();
      }
    } catch (_) {
      _productsByStore[storeId] = _fallbackProducts.where((p) => p.storeId == storeId).toList();
    }
  }

  Future<void> _prefetchAllProducts() async {
    await Future.wait(_stores.map((s) => _fetchProductsForStore(s.id)));
  }

  Future<bool> selectStore(Store store) async {
    final switched = _selectedStore != null && _selectedStore!.id != store.id;
    if (switched && _cart.isNotEmpty) {
      _cart.clear();
    }
    _selectedStore = store;
    await _fetchProductsForStore(store.id);
    _deliveryPoint = LatLng(store.latitude + 0.01, store.longitude + 0.01);
    notifyListeners();
    return switched;
  }

  void setDeliveryPoint(LatLng point) {
    _deliveryPoint = point;
    _deliveryAddress = '';
    notifyListeners();
  }

  Future<bool> setDeliveryByQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': trimmed,
        'format': 'json',
        'limit': '1',
      });
      final resp = await http.get(uri, headers: {'User-Agent': 'drone_delivery_app/1.0'});
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final first = data.first as Map<String, dynamic>;
          final lat = double.parse(first['lat'] as String);
          final lon = double.parse(first['lon'] as String);
          _deliveryPoint = LatLng(lat, lon);
          _deliveryAddress = (first['display_name'] as String?) ?? '';
          notifyListeners();
          return true;
        }
      }
    } catch (_) {
      // ignore
    }
    return false;
  }

  void addToCart(Product product) {
    if (_selectedStore == null) return;
    if (product.storeId != _selectedStore!.id) return;
    final current = _cart[product.id];
    if (current == null) {
      _cart[product.id] = CartItem(product: product, quantity: 1);
    } else {
      _cart[product.id] = current.copyWith(quantity: current.quantity + 1);
    }
    notifyListeners();
  }

  void increment(String productId) {
    final item = _cart[productId];
    if (item == null) return;
    _cart[productId] = item.copyWith(quantity: item.quantity + 1);
    notifyListeners();
  }

  void decrement(String productId) {
    final item = _cart[productId];
    if (item == null) return;
    if (item.quantity <= 1) {
      _cart.remove(productId);
    } else {
      _cart[productId] = item.copyWith(quantity: item.quantity - 1);
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  void payAndLaunch({bool useBackendTracking = false}) {
    if (_cart.isEmpty || isOverweight || _selectedStore == null) return;
    _useBackendTracking = useBackendTracking;
    final newOrder = Order(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      items: cartItems,
      totalWeight: totalWeight,
      destination: GeoPoint(latitude: _deliveryPoint.latitude, longitude: _deliveryPoint.longitude),
      status: OrderStatus.processing,
    );
    _activeOrder = newOrder;
    _startFlight();
  }

  void _startFlight() {
    _flightTimer?.cancel();
    _backendDronePosition = null;
    _droneIndex = 0;
    _updateOrderStatus(OrderStatus.flying);

    if (_useBackendTracking) {
      _flightTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollBackendPosition());
      return;
    }

    final start = _selectedStore == null
        ? LatLng(43.238949, 76.889709)
        : LatLng(_selectedStore!.latitude, _selectedStore!.longitude);
    final end = _deliveryPoint;
    _flightPath = _buildPath(start, end);

    _flightTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_droneIndex < _flightPath.length - 1) {
        _droneIndex++;
        notifyListeners();
        return;
      }
      timer.cancel();
      _droneIndex = _flightPath.length - 1;
      _updateOrderStatus(OrderStatus.delivered);
    });
    notifyListeners();
  }

  Future<void> _pollBackendPosition() async {
    if (_activeOrder == null) return;
    try {
        final store = _selectedStore;
        final startLat = store?.latitude ?? 43.238949;
        final startLng = store?.longitude ?? 76.889709;
        final endLat = _deliveryPoint.latitude;
        final endLng = _deliveryPoint.longitude;
        final uri = Uri.parse(
          '$backendBaseUrl/drone/position?orderId=${_activeOrder!.id}&start_lat=$startLat&start_lng=$startLng&end_lat=$endLat&end_lng=$endLng');
        final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        final delivered = data['delivered'] == true;
        _backendDronePosition = LatLng(lat, lng);
        if (delivered) {
          _backendDronePosition = LatLng(endLat, endLng);
          _updateOrderStatus(OrderStatus.delivered);
          _flightTimer?.cancel();
        }
        notifyListeners();
      }
    } catch (_) {
      // fallback: do nothing on error
    }
  }

  void _updateOrderStatus(OrderStatus status) {
    if (_activeOrder == null) return;
    _activeOrder = _activeOrder!.copyWith(status: status);
    notifyListeners();
  }

  List<LatLng> _buildPath(LatLng start, LatLng end, {int steps = 100}) {
    return List.generate(steps, (i) {
      final t = i / (steps - 1);
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      return LatLng(lat, lng);
    });
  }

  List<Store> get _fallbackStores {
    return List.generate(3, (i) {
      final baseLat = 43.235 + i * 0.002;
      final baseLng = 76.88 + i * 0.003;
      return Store(
        id: 's${i + 1}',
        name: 'Магазин ${i + 1}',
        address: 'Алматы, проспект Абая ${50 + i}',
        latitude: baseLat,
        longitude: baseLng,
      );
    });
  }

  List<Product> get _fallbackProducts {
    final stores = _fallbackStores;
    final List<Product> result = [];
    final imageUrls = [
      'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=400&q=80',
      'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=400&q=80',
      'https://images.unsplash.com/photo-1572635196237-14b3f281503f?auto=format&fit=crop&w=400&q=80',
      'https://images.unsplash.com/photo-1560343090-f0409e92791a?auto=format&fit=crop&w=400&q=80',
      'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=400&q=80',
    ];
    final titles = [
      'Беспроводные наушники Pro',
      'Умные часы Sport',
      'Портативная колонка',
      'Солнцезащитные очки',
      'Кроссовки Premium',
    ];
    for (final store in stores) {
      for (int i = 0; i < 5; i++) {
        result.add(Product(
          id: '${store.id}_p${i + 1}',
          storeId: store.id,
          title: '${titles[i]} · ${store.name}',
          price: 1500 + (i * 150),
          weight: 200 + i * 30,
          imageUrl: imageUrls[i],
        ));
      }
    }
    return result;
  }

  @override
  void dispose() {
    _flightTimer?.cancel();
    super.dispose();
  }
}
