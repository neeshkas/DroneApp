import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../state/app_state.dart';
import 'tracking_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void dispose() {
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
                        child: _AddressRow(
                          address: appState.deliveryAddress,
                          onTap: () async {
                            await Navigator.of(context).push(
                              PageRouteBuilder(
                                opaque: false,
                                pageBuilder: (_, __, ___) => const _AddressPickerScreen(),
                                transitionsBuilder: (_, animation, __, child) {
                                  final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                                  final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
                                  final slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(fade);
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: slide,
                                      child: ScaleTransition(scale: scale, child: child),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: 'Receipt',
                          subtitle: '${items.length} item${items.length == 1 ? '' : 's'}',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _ReceiptItemRow(
                            item: item,
                            onDecrement: () => context.read<AppState>().decrement(item.product.id),
                            onIncrement: () => context.read<AppState>().increment(item.product.id),
                          );
                        },
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _ReceiptTotals(total: appState.totalPrice),
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

class _ReceiptItemRow extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _ReceiptItemRow({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineTotal = item.product.price * item.quantity;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.product.title,
              style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.quantity} x KZT ${item.product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                ),
                Text(
                  'KZT ${lineTotal.toStringAsFixed(0)}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  onPressed: onDecrement,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  item.quantity.toString(),
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
                IconButton(
                  onPressed: onIncrement,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  color: theme.colorScheme.primary,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
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

class _ReceiptTotals extends StatelessWidget {
  final double total;
  const _ReceiptTotals({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _ReceiptLine(label: 'SUBTOTAL', value: 'KZT ${total.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _ReceiptLine(label: 'DELIVERY', value: 'KZT 0'),
          const Divider(height: 16),
          _ReceiptLine(
            label: 'TOTAL',
            value: 'KZT ${total.toStringAsFixed(0)}',
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _ReceiptLine({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.jetBrainsMono(
      fontSize: strong ? 13 : 11,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  final String address;
  final VoidCallback onTap;

  const _AddressRow({required this.address, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.place_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                address,
                style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right),
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

class _AddressPickerScreen extends StatefulWidget {
  const _AddressPickerScreen();

  @override
  State<_AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<_AddressPickerScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<GeoSuggestion> _suggestions = [];
  bool _isLoading = false;
  LatLng? _tempPoint;
  String? _tempAddress;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _tempPoint = appState.deliveryPoint;
    _tempAddress = appState.deliveryAddress;
    _controller.text = appState.deliveryAddress;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions.clear();
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    final results = await context.read<AppState>().searchAddressSuggestions(query);
    if (!mounted) return;
    setState(() {
      _suggestions
        ..clear()
        ..addAll(results);
      _isLoading = false;
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(value));
  }

  Future<void> _selectSuggestion(GeoSuggestion suggestion) async {
    setState(() {
      _tempPoint = suggestion.point;
      _tempAddress = suggestion.address;
      _suggestions.clear();
    });
    await context.read<AppState>().setDeliveryPointFromMap(suggestion.point);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickOnMap(LatLng point) async {
    await context.read<AppState>().setDeliveryPointFromMap(point);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<AppState>().selectedStore;
    final start = store != null ? LatLng(store.latitude, store.longitude) : AppState.fallbackClient;
    final center = _tempPoint ?? AppState.fallbackClient;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select delivery address',
                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Search address',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: _fetchSuggestions,
              ),
            ),
            if (_suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: theme.colorScheme.primary.withOpacity(0.1)),
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          suggestion.address,
                          style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        onTap: () => _selectSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  children: [
                    FlutterMap(
                      key: ValueKey('picker-map-${context.watch<AppState>().mapTick}'),
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 13,
                        onTap: (_, point) => _pickOnMap(point),
                        interactionOptions:
                            const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          tileProvider: CancellableNetworkTileProvider(),
                          retinaMode: true,
                          userAgentPackageName: 'com.droneapp.demo',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: center,
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
                      right: 10,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                        ),
                        child: Text(
                          '© OpenStreetMap contributors',
                          style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_tempAddress != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12)],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.place_outlined, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _tempAddress!,
                                  style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
