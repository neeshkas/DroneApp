import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final start = store != null ? LatLng(store.latitude, store.longitude) : AppState.fallbackClient;
    final end = appState.deliveryPoint;
    final theme = Theme.of(context);

    if (appState.deliveryId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live flight')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined, size: 56, color: theme.colorScheme.primary.withOpacity(0.4)),
                const SizedBox(height: 12),
                Text(
                  'No active delivery.',
                  style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Place an order to start tracking your drone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to catalog'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Live flight')),
      body: Column(
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
                  tileProvider: CancellableNetworkTileProvider(),
                  retinaMode: true,
                  userAgentPackageName: 'com.droneapp.demo',
                ),
                if (path.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: path, color: theme.colorScheme.secondary.withOpacity(0.9), strokeWidth: 4),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(point: start, child: const _HudMarker(icon: Icons.storefront)),
                    Marker(point: end, child: const _HudMarker(icon: Icons.flag)),
                    Marker(point: dronePoint, child: const _DroneMarker()),
                  ],
                ),
              ],
            ),
          ),
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.fromLTRB(0, 6, 12, 0),
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 10),
            ),
          ),
          _StatusPanel(
            status: appState.statusLabel,
            orderId: appState.deliveryId!,
            isDelivered: appState.isDelivered,
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final String status;
  final String orderId;
  final bool isDelivered;
  const _StatusPanel({required this.status, required this.orderId, required this.isDelivered});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15), width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Delivery status',
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sora(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusChip(icon: Icons.timer_outlined, label: 'ETA 5-8 min'),
                        _StatusChip(icon: Icons.shield_outlined, label: 'Secure payload'),
                        _StatusChip(icon: Icons.confirmation_number_outlined, label: orderId),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isDelivered)
                      _QrCodeSection(orderId: orderId)
                    else
                      Text(
                        'Your drone is en route. You will get a QR code when it lands.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _QrCodeSection extends StatelessWidget {
  final String orderId;
  const _QrCodeSection({required this.orderId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Delivery arrived',
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF059669),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.secondary.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                )
              ],
            ),
            child: QrImageView(
              data: '{"order_id": "$orderId", "action": "confirm_delivery"}',
              version: QrVersions.auto,
              size: 150.0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Show this QR code to confirm receipt.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8)),
        ),
      ],
    );
  }
}

class _HudMarker extends StatelessWidget {
  final IconData icon;
  const _HudMarker({required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(icon, color: theme.colorScheme.primary.withOpacity(0.9), size: 30);
  }
}

class _DroneMarker extends StatefulWidget {
  const _DroneMarker();

  @override
  State<_DroneMarker> createState() => _DroneMarkerState();
}

class _DroneMarkerState extends State<_DroneMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: const _PulsingCurve())),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _PulseRing(size: 52, color: theme.colorScheme.secondary.withOpacity(0.2)),
          _PulseRing(size: 36, color: theme.colorScheme.secondary.withOpacity(0.45)),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.secondary.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: const Icon(Icons.flight_rounded, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  final double size;
  final Color color;

  const _PulseRing({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PulsingCurve extends Curve {
  const _PulsingCurve();
  @override
  double transform(double t) {
    if (t < 0.5) return 2.0 * t;
    return 2.0 * (1.0 - t);
  }
}
