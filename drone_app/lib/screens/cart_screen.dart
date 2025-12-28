import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../models/store.dart';
import '../state/app_state.dart';
import 'tracking_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
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
    final items = appState.cartItems;
    final theme = Theme.of(context);
    final canPay = !appState.isCartEmpty && !appState.isOverweight;

    return Scaffold(
      appBar: AppBar(title: const Text('Your order')),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_bag_outlined, size: 56, color: theme.colorScheme.primary.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text(
                      'Your cart is empty.',
                      style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pick a store and add the essentials you want delivered.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Browse stores'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: 'Cart',
                          subtitle: '${items.length} item${items.length == 1 ? '' : 's'}',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _CartItemRow(
                            item: item,
                            onDecrement: () => context.read<AppState>().decrement(item.product.id),
                            onIncrement: () => context.read<AppState>().increment(item.product.id),
                          );
                        },
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: 'Delivery',
                          subtitle: 'Drop a pin or search an address',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _MapCard(
                          store: appState.selectedStore,
                          delivery: appState.deliveryPoint,
                          onPick: (p) => context.read<AppState>().setDeliveryPointFromMap(p),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: TextField(
                          controller: _addressCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search street, building, or landmark',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : null,
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (query) async {
                            if (_isSearching || query.isEmpty) return;
                            setState(() => _isSearching = true);
                            final ok = await context.read<AppState>().setDeliveryByQuery(query);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? 'Delivery point updated.' : 'Unable to find that location.'),
                                ),
                              );
                            }
                            setState(() => _isSearching = false);
                          },
                        ),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 220)),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _CartSummary(
                    total: appState.totalPrice,
                    totalWeight: appState.totalWeight,
                    isOverweight: appState.isOverweight,
                    isDisabled: !canPay,
                    onCheckout: () {
                      context.read<AppState>().payAndLaunch(useBackendTracking: true);
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const TrackingScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
        ),
      ],
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _CartItemRow({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Image.network(
              item.product.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.inventory_2_outlined,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.title,
                  style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'KZT ${item.product.price.toStringAsFixed(0)}',
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.background,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onDecrement,
                  icon: const Icon(Icons.remove_circle_outline, size: 24),
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                Text(
                  item.quantity.toString(),
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                IconButton(
                  onPressed: onIncrement,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  final double total;
  final double totalWeight;
  final bool isOverweight;
  final bool isDisabled;
  final VoidCallback onCheckout;

  const _CartSummary({
    required this.total,
    required this.totalWeight,
    required this.isOverweight,
    required this.isDisabled,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const weightLimit = 3000.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15), width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, spreadRadius: 2)],
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Column(
                  children: [
                    _InfoRow(
                      label: 'Subtotal',
                      value: 'KZT ${total.toStringAsFixed(0)}',
                      valueStyle: GoogleFonts.sora(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Payload weight',
                      value: '${totalWeight.toStringAsFixed(0)} / ${weightLimit.toStringAsFixed(0)} g',
                      valueStyle: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isOverweight ? const Color(0xFFB45309) : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (isOverweight)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 20),
                            Text(
                              'Over the drone limit. Reduce to ${(weightLimit / 1000).toStringAsFixed(1)} kg.',
                              style: GoogleFonts.sora(color: const Color(0xFFB45309), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isDisabled ? null : onCheckout,
                        icon: const Icon(Icons.send_and_archive_outlined, size: 20),
                        label: const Text('Place order'),
                      ),
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

class _MapCard extends StatelessWidget {
  final Store? store;
  final LatLng delivery;
  final ValueChanged<LatLng> onPick;

  const _MapCard({required this.store, required this.delivery, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final start = store != null ? LatLng(store!.latitude, store!.longitude) : AppState.fallbackClient;
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 240,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: delivery,
                initialZoom: 13,
                onTap: (_, point) => onPick(point),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  tileProvider: CancellableNetworkTileProvider(),
                  retinaMode: true,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: delivery,
                      child: _PinMarker(icon: Icons.location_on, color: theme.colorScheme.secondary),
                    ),
                    Marker(
                      point: start,
                      child: _PinMarker(icon: Icons.storefront, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                ),
                child: Text(
                  'Tap map to adjust drop point',
                  style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _PinMarker({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.circle, color: color.withOpacity(0.2), size: 46),
        Icon(icon, color: color, size: 26),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _InfoRow({required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: valueStyle ??
                GoogleFonts.sora(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
          ),
        ),
      ],
    );
  }
}
