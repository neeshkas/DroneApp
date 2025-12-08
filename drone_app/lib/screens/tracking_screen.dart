import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/app_state.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final path = appState.flightPath;
    final dronePoint = appState.dronePosition;
    final store = appState.selectedStore;
    final start = store != null
        ? LatLng(store.latitude, store.longitude)
        : AppState.fallbackClient;
    final end = appState.deliveryPoint;

    return Scaffold(
      appBar: AppBar(title: const Text('Трекинг')),
      body: SafeArea(
        child: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: start,
                initialZoom: 13,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.drone_app',
                ),
                if (path.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: path, color: Colors.blueAccent, strokeWidth: 4),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: start,
                      width: 40,
                      height: 40,
                      child: const _Marker(label: 'A'),
                    ),
                    Marker(
                      point: end,
                      width: 40,
                      height: 40,
                      child: const _Marker(label: 'B'),
                    ),
                    Marker(
                      point: dronePoint,
                      width: 44,
                      height: 44,
                      child: const _DroneMarker(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _StatusPanel(status: appState.statusLabel, isDelivered: appState.isDelivered),
        ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final String status;
  final bool isDelivered;
  const _StatusPanel({required this.status, required this.isDelivered});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, -4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (isDelivered)
            Center(
              child: FilledButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Заказ получен!')), // minimal acknowledgment
                  );
                },
                child: const Text('Получить'),
              ),
            )
          else
            const Text('Следите за движением дрона на карте.'),
        ],
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  final String label;
  const _Marker({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
      child: Center(
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _DroneMarker extends StatelessWidget {
  const _DroneMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: const Icon(Icons.airplanemode_active, color: Colors.white),
    );
  }
}
