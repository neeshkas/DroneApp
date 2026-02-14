import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../utils/ws_client.dart';

class AppState extends ChangeNotifier {
  // Mock backend URL
  static String _normalizeWebHost(String host) {
    if (host.isEmpty || host == 'localhost' || host == '::1') {
      return '127.0.0.1';
    }
    return host;
  }

  static String get _orderApiBaseUrl {
    if (kIsWeb) {
      final base = Uri.base;
      final host = _normalizeWebHost(base.host);
      final scheme = (base.scheme == 'https' || base.scheme == 'http') ? base.scheme : 'http';
      return '$scheme://$host:18000';
    }
    return 'http://127.0.0.1:18000';
  }

  static String get _trackingBaseUrl {
    if (kIsWeb) {
      final base = Uri.base;
      final host = _normalizeWebHost(base.host);
      final scheme = (base.scheme == 'https' || base.scheme == 'http') ? base.scheme : 'http';
      return '$scheme://$host:18002';
    }
    return 'http://127.0.0.1:18002';
  }

  static String _buildTrackingWsUrl(String deliveryId, String token) {
    if (kIsWeb) {
      final base = Uri.base;
      final host = _normalizeWebHost(base.host);
      final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
      return '$wsScheme://$host:18002/ws/track/$deliveryId?token=$token';
    }
    return 'ws://127.0.0.1:18002/ws/track/$deliveryId?token=$token';
  }

  // WebSocket connection
  WsClient? _ws;
  StreamSubscription? _subscription;
  Timer? _httpTrackingTimer;
  bool _httpFallbackActive = false;

  List<Store> stores = [];
  List<Product> _allProducts = [];
  List<CartItem> cartItems = [];
  Store? selectedStore;
  String? deliveryId;
  String? trackingAccessToken;
  String? trackingRefreshToken;

  // Delivery
  LatLng deliveryPoint = fallbackClient;
  String deliveryAddress = 'Set delivery point';

  // Tracking
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
      final response = await http.get(Uri.parse('$_orderApiBaseUrl/stores'));
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
      final response = await http.get(Uri.parse('$_orderApiBaseUrl/products'));
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

  Future<void> setDeliveryPointFromMap(LatLng point) async {
    deliveryPoint = point;
    deliveryAddress = 'Resolving address...';
    notifyListeners();

    final resolved = await _reverseGeocode(point);
    if (resolved != null) {
      deliveryAddress = resolved;
    } else {
      deliveryAddress = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    }
    notifyListeners();
  }

  Future<bool> setDeliveryByQuery(String query) async {
    if (query.trim().isEmpty) return false;
    final result = await _geocode(query.trim());
    if (result == null) return false;
    deliveryPoint = result.point;
    deliveryAddress = result.address;
    notifyListeners();
    return true;
  }

  Future<_GeoResult?> _geocode(String query) async {
    try {
      final uri = Uri.parse('$_orderApiBaseUrl/geocode').replace(queryParameters: {'q': query});
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      if (data.isEmpty) return null;
      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      final address = first['display_name']?.toString();
      if (lat == null || lon == null || address == null) return null;
      return _GeoResult(LatLng(lat, lon), address);
    } catch (e) {
      debugPrint('Geocode error: $e');
      return null;
    }
  }

  Future<String?> _reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.parse('$_orderApiBaseUrl/reverse-geocode').replace(queryParameters: {
        'lat': point.latitude.toString(),
        'lng': point.longitude.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final data = json.decode(utf8.decode(response.bodyBytes));
      final address = data['display_name']?.toString();
      return address;
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      return null;
    }
  }

  void payAndLaunch({required bool useBackendTracking}) {
    if (isCartEmpty || selectedStore == null) return;
    deliveryId = null;
    trackingAccessToken = null;
    trackingRefreshToken = null;
    isDelivered = false;
    statusLabel = 'Preparing drone and loading payload...';

    _createDelivery(useBackendTracking: useBackendTracking);
    notifyListeners();
  }

  Future<void> _createDelivery({required bool useBackendTracking}) async {
    final start = selectedStore != null ? LatLng(selectedStore!.latitude, selectedStore!.longitude) : fallbackClient;
    final end = deliveryPoint;
    try {
      final response = await http.post(
        Uri.parse('$_orderApiBaseUrl/deliveries'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'store_id': selectedStore!.id,
          'start_lat': start.latitude,
          'start_lng': start.longitude,
          'end_lat': end.latitude,
          'end_lng': end.longitude,
        }),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        statusLabel = 'Failed to create delivery';
        notifyListeners();
        return;
      }
      final data = json.decode(utf8.decode(response.bodyBytes));
      deliveryId = data['delivery_id'] as String?;
      trackingAccessToken = data['tracking_access_token'] as String?;
      trackingRefreshToken = data['tracking_refresh_token'] as String?;
      if (deliveryId == null || trackingAccessToken == null) {
        statusLabel = 'Invalid delivery response';
        notifyListeners();
        return;
      }
      if (useBackendTracking) {
        _startWebSocketTracking();
      } else {
        _startHttpTracking();
      }
    } catch (e) {
      statusLabel = 'Failed to create delivery';
      debugPrint('Create delivery error: $e');
    }
    notifyListeners();
  }

  Future<void> _startWebSocketTracking() async {
    final start = selectedStore != null ? LatLng(selectedStore!.latitude, selectedStore!.longitude) : fallbackClient;
    final end = deliveryPoint;

    flightPath = [start, end];
    dronePosition = start;

    // Close any existing connection
    _subscription?.cancel();
    _ws?.close();
    _stopHttpTracking();
    _httpFallbackActive = false;

    // Connect to WebSocket
    try {
      if (deliveryId == null || trackingAccessToken == null) {
        statusLabel = 'Missing tracking token';
        return;
      }
      final wsUrl = _buildTrackingWsUrl(deliveryId!, trackingAccessToken!);
      debugPrint('Connecting to WS: $wsUrl');
      _ws = await WsClient.connect(wsUrl);

      // Listen for messages from server
      _subscription = _ws!.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          statusLabel = 'Connection error: $error';
          _startHttpTracking();
          notifyListeners();
        },
        onDone: () {
          debugPrint('WebSocket closed');
          if (!isDelivered) {
            _startHttpTracking();
          }
        },
      );

      statusLabel = 'Tracking drone...';
    } catch (e) {
      debugPrint('Failed to connect to WebSocket: $e');
      statusLabel = 'Connection failed';
      _startHttpTracking();
    }

    notifyListeners();
  }

  Future<void> _startHttpTracking() async {
    if (_httpFallbackActive) return;
    if (deliveryId == null) return;

    _httpFallbackActive = true;
    _stopHttpTracking();
    statusLabel = 'Tracking via HTTP...';
    notifyListeners();

    Future<void> fetchOnce() async {
      final start = selectedStore != null ? LatLng(selectedStore!.latitude, selectedStore!.longitude) : fallbackClient;
      final end = deliveryPoint;
      try {
        final uri = Uri.parse('$_trackingBaseUrl/track/$deliveryId');
        final response = await http.get(uri, headers: {
          if (trackingAccessToken != null) 'Authorization': 'Bearer $trackingAccessToken',
        });
        if (response.statusCode == 401 && trackingRefreshToken != null) {
          final refreshed = await _refreshAccessToken();
          if (!refreshed) return;
        }
        if (response.statusCode != 200) return;
        final data = json.decode(utf8.decode(response.bodyBytes));
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        final delivered = data['status'] == 'DELIVERED';

        dronePosition = LatLng(lat, lng);
        isDelivered = delivered;
        statusLabel = delivered ? 'Delivered' : data['status'] as String? ?? 'In flight';
        notifyListeners();

        if (delivered) {
          _stopHttpTracking();
          _httpFallbackActive = false;
        }
      } catch (e) {
        debugPrint('HTTP tracking error: $e');
      }
    }

    await fetchOnce();
    _httpTrackingTimer = Timer.periodic(const Duration(seconds: 5), (_) => fetchOnce());
  }

  void _stopHttpTracking() {
    _httpTrackingTimer?.cancel();
    _httpTrackingTimer = null;
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      if (message is String) {
        final data = json.decode(message);

        if (data['lat'] != null && data['lng'] != null) {
          dronePosition = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
          isDelivered = data['status'] == 'DELIVERED';
          statusLabel = data['status'] as String? ?? 'In flight';

          if (isDelivered) {
            statusLabel = 'Delivered';
            _subscription?.cancel();
            _ws?.close();
            _stopHttpTracking();
            _httpFallbackActive = false;
          }

          notifyListeners();
        } else if (data['type'] == 'error') {
          debugPrint('Server error: ${data['message']}');
          statusLabel = 'Error: ${data['message']}';
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  Future<bool> _refreshAccessToken() async {
    try {
      final response = await http.post(
        Uri.parse('$_orderApiBaseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh_token': trackingRefreshToken}),
      );
      if (response.statusCode != 200) return false;
      final data = json.decode(utf8.decode(response.bodyBytes));
      trackingAccessToken = data['access_token'] as String?;
      return trackingAccessToken != null;
    } catch (e) {
      debugPrint('Refresh token error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ws?.close();
    _stopHttpTracking();
    super.dispose();
  }
}

class _GeoResult {
  final LatLng point;
  final String address;
  const _GeoResult(this.point, this.address);
}
