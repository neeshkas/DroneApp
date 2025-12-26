import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/store.dart';

class AppState extends ChangeNotifier {
  // Mock backend URL
  static const String _baseUrl = 'http://127.0.0.1:8000';

  List<Store> stores = [];
  List<Product> _allProducts = [];
  List<CartItem> cartItems = [];
  Store? selectedStore;
  String? orderId;

  // Delivery
  LatLng deliveryPoint = fallbackClient;
  String deliveryAddress = 'Set delivery point';

  // Tracking
  Timer? _trackingTimer;
  List<LatLng> flightPath = [];
  LatLng dronePosition = fallbackClient;
  String statusLabel = 'Waiting for dispatch';
  bool isDelivered = false;

  static final fallbackClient = LatLng(43.238949, 76.889709); // Almaty

  bool get isCartEmpty => cartItems.isEmpty;
  double get totalPrice => cartItems.fold(0, (sum, item) => sum + item.product.price * item.quantity);
  double get totalWeight => cartItems.fold(0, (sum, item) => sum + item.product.weight * item.quantity);
  bool get isOverweight => totalWeight > 3000; // 3kg limit

  Future<void> init() async {
    await _fetchStores();
    if (stores.isNotEmpty) {
      await _fetchAllProducts();
      selectedStore = stores.first;
      deliveryPoint = LatLng(selectedStore!.latitude + 0.02, selectedStore!.longitude + 0.02);
      deliveryAddress = 'Kaskelen';
    }
    notifyListeners();
  }

  Future<void> _fetchStores() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/stores'));
      if (response.statusCode == 200) {
        final List<dynamic> storeJson = json.decode(utf8.decode(response.bodyBytes));
        stores = storeJson.map((json) => Store.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load stores: $e');
    }
  }

  Future<void> _fetchAllProducts() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/products'));
      if (response.statusCode == 200) {
        final List<dynamic> productJson = json.decode(utf8.decode(response.bodyBytes));
        _allProducts = productJson.map((json) => Product.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load products: $e');
    }
  }

  Future<bool> selectStore(Store store) async {
    bool switched = false;
    if (selectedStore?.id != store.id) {
      selectedStore = store;
      if (cartItems.isNotEmpty) {
        cartItems.clear();
        switched = true;
      }
      notifyListeners();
    }
    return switched;
  }

  void addToCart(Product product) {
    if (selectedStore == null) return;
    if (cartItems.any((item) => item.product.id == product.id)) {
      increment(product.id);
    } else {
      cartItems.add(CartItem(product: product, quantity: 1));
    }
    notifyListeners();
  }

  void increment(String productId) {
    final index = cartItems.indexWhere((item) => item.product.id == productId);
    if (index != -1) {
      cartItems[index] = cartItems[index].copyWith(quantity: cartItems[index].quantity + 1);
      notifyListeners();
    }
  }

  void decrement(String productId) {
    final index = cartItems.indexWhere((item) => item.product.id == productId);
    if (index != -1) {
      if (cartItems[index].quantity > 1) {
        cartItems[index] = cartItems[index].copyWith(quantity: cartItems[index].quantity - 1);
      } else {
        cartItems.removeAt(index);
      }
      notifyListeners();
    }
  }

  List<Product> productsForStore(String storeId) {
    return _allProducts.where((p) => p.storeId == storeId).toList();
  }

  void setDeliveryPoint(LatLng point) {
    deliveryPoint = point;
    deliveryAddress = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    notifyListeners();
  }

  Future<bool> setDeliveryByQuery(String query) async {
    // Mock search - in a real app this would call a geocoding API
    await Future.delayed(const Duration(milliseconds: 500));
    deliveryPoint = LatLng(deliveryPoint.latitude + 0.01, deliveryPoint.longitude + 0.01);
    deliveryAddress = query;
    notifyListeners();
    return true;
  }

  void payAndLaunch({required bool useBackendTracking}) {
    if (isCartEmpty || selectedStore == null) return;
    orderId = 'ORDER-${Random().nextInt(99999)}';
    isDelivered = false;
    statusLabel = 'Preparing drone and loading payload...';

    if (useBackendTracking) {
      _startBackendTracking();
    } else {
      _startBackendTracking();
    }
    notifyListeners();
  }

  void _startBackendTracking() {
    _trackingTimer?.cancel();
    final start = selectedStore != null ? LatLng(selectedStore!.latitude, selectedStore!.longitude) : fallbackClient;
    final end = deliveryPoint;

    flightPath = [start, end];
    dronePosition = start;

    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchDronePosition(start, end));
  }

  Future<void> _fetchDronePosition(LatLng start, LatLng end) async {
    if (orderId == null) {
      _trackingTimer?.cancel();
      return;
    }

    final uri = Uri.parse('$_baseUrl/drone/position').replace(queryParameters: {
      'orderId': orderId!,
      'start_lat': start.latitude.toString(),
      'start_lng': start.longitude.toString(),
      'end_lat': end.latitude.toString(),
      'end_lng': end.longitude.toString(),
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        dronePosition = LatLng(data['lat'], data['lng']);
        isDelivered = data['delivered'] ?? false;

        if (isDelivered) {
          statusLabel = 'Delivered';
          _trackingTimer?.cancel();
        } else {
          statusLabel = 'In flight';
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to fetch drone position: $e');
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }
}
