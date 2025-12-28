import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/store.dart';
import '../state/app_state.dart';

class CheckoutScreen extends StatefulWidget {
  final VoidCallback onStartTracking;
  const CheckoutScreen({super.key, required this.onStartTracking});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool deliverToKiosk = true;
  final TextEditingController _addressCtrl = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canPay = !appState.isCartEmpty && !appState.isOverweight;
    final store = appState.selectedStore;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MapCard(
                store: store,
                delivery: appState.deliveryPoint,
                onPick: (p) => context.read<AppState>().setDeliveryPointFromMap(p),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Delivery preferences', style: Theme.of(context).textTheme.titleMedium),
                  Row(
                    children: [
                      const Text('Kiosk'),
                      Switch(
                        value: !deliverToKiosk,
                        onChanged: (v) => setState(() => deliverToKiosk = !deliverToKiosk),
                      ),
                      const Text('To door'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal'),
                  Text('KZT ${appState.totalPrice.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Weight'),
                  Text('${appState.totalWeight.toStringAsFixed(0)} g'),
                ],
              ),
              const SizedBox(height: 4),
              Text('Delivery address: ${appState.deliveryAddress}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Search address',
                  hintText: 'Street, building, or landmark',
                  suffixIcon: IconButton(
                    icon: _isSearching
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    onPressed: _isSearching
                        ? null
                        : () async {
                            setState(() => _isSearching = true);
                            final ok = await context.read<AppState>().setDeliveryByQuery(_addressCtrl.text);
                            setState(() => _isSearching = false);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Delivery point updated.' : 'Unable to find that location.')),
                            );
                          },
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async {
                  if (_isSearching) return;
                  setState(() => _isSearching = true);
                  final ok = await context.read<AppState>().setDeliveryByQuery(_addressCtrl.text);
                  setState(() => _isSearching = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Delivery point updated.' : 'Unable to find that location.')),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (store != null)
                Text('Selected store: ${store.name}\nAddress: ${store.address}',
                    style: Theme.of(context).textTheme.bodySmall),
              if (appState.isOverweight)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      const Text('Payload is over 3 kg'),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canPay
                        ? () {
                            context.read<AppState>().payAndLaunch(useBackendTracking: true);
                            widget.onStartTracking();
                          }
                        : null,
                    child: const Text('Pay and launch'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  final Store? store;
  final LatLng delivery;
  final ValueChanged<LatLng> onPick;

  const _MapCard({required this.store, required this.delivery, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final start = store != null ? LatLng(store!.latitude, store!.longitude) : AppState.fallbackClient;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: delivery,
            initialZoom: 13,
            onTap: (_, point) => onPick(point),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.drone_app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: delivery,
                  width: 36,
                  height: 36,
                  child: const _PinMarker(label: 'B', color: Colors.green),
                ),
                Marker(
                  point: start,
                  width: 36,
                  height: 36,
                  child: const _PinMarker(label: 'A', color: Colors.black),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PinMarker extends StatelessWidget {
  final String label;
  final Color color;
  const _PinMarker({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
