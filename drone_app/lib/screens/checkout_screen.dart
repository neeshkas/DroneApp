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
      appBar: AppBar(title: const Text('Оформление')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MapCard(
                store: store,
                delivery: appState.deliveryPoint,
                onPick: (p) => context.read<AppState>().setDeliveryPoint(p),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Способ доставки', style: Theme.of(context).textTheme.titleMedium),
                  Row(
                    children: [
                      const Text('Киоск'),
                      Switch(
                        value: !deliverToKiosk,
                        onChanged: (v) => setState(() => deliverToKiosk = !deliverToKiosk),
                      ),
                      const Text('Лебёдка'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Итого'),
                  Text('₸${appState.totalPrice.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Вес'),
                  Text('${appState.totalWeight.toStringAsFixed(0)} г'),
                ],
              ),
              const SizedBox(height: 4),
              Text('Точка доставки: ${appState.deliveryAddress}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Нажмите на карту выше, чтобы выбрать точку доставки, или введите адрес',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Поиск адреса',
                  hintText: 'Например: Алматы, Абая 50',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  suffixIcon: IconButton(
                    icon: _isSearching
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    onPressed: _isSearching
                        ? null
                        : () async {
                            if (_addressCtrl.text.trim().isEmpty) return;
                            setState(() => _isSearching = true);
                            final ok = await context.read<AppState>().setDeliveryByQuery(_addressCtrl.text);
                            setState(() => _isSearching = false);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(ok ? Icons.check_circle : Icons.error, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(ok
                                        ? 'Адрес найден! Точка обновлена на карте'
                                        : 'Не удалось найти адрес. Попробуйте выбрать точку на карте'),
                                    ),
                                  ],
                                ),
                                backgroundColor: ok ? Colors.green.shade600 : Colors.orange.shade700,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async {
                  if (_isSearching || _addressCtrl.text.trim().isEmpty) return;
                  setState(() => _isSearching = true);
                  final ok = await context.read<AppState>().setDeliveryByQuery(_addressCtrl.text);
                  setState(() => _isSearching = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(ok ? Icons.check_circle : Icons.error, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(ok
                              ? 'Адрес найден! Точка обновлена на карте'
                              : 'Не удалось найти адрес. Попробуйте выбрать точку на карте'),
                          ),
                        ],
                      ),
                      backgroundColor: ok ? Colors.green.shade600 : Colors.orange.shade700,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              if (store != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.store, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(store.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(store.address, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (appState.isOverweight)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      const Text('Перегруз > 3 кг'),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12),
                child: SizedBox(
                  width: double.infinity,
                  child: AnimatedPayButton(
                    onPressed: canPay
                        ? () {
                            context.read<AppState>().payAndLaunch(useBackendTracking: true);
                            widget.onStartTracking();
                          }
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apple, size: 20),
                        const SizedBox(width: 8),
                        const Text('Оплатить Apple Pay'),
                      ],
                    ),
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
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))]),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class AnimatedPayButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const AnimatedPayButton({super.key, required this.onPressed, required this.child});

  @override
  State<AnimatedPayButton> createState() => _AnimatedPayButtonState();
}

class _AnimatedPayButtonState extends State<AnimatedPayButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FilledButton(
          onPressed: widget.onPressed == null
              ? null
              : () {
                  _controller.forward().then((_) => _controller.reverse());
                  widget.onPressed!();
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: _isHovered && widget.onPressed != null ? Colors.black : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: _isHovered ? 4 : 0,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
