import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/store.dart';
import '../state/app_state.dart';
import 'cart_screen.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final itemsInCart = appState.cartItems.fold<int>(0, (sum, item) => sum + item.quantity);
    final stores = appState.stores;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyDrop'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen()));
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 28),
                if (itemsInCart > 0)
                  Positioned(
                    right: -8,
                    top: -5,
                    child: _Badge(label: itemsInCart.toString()),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: stores.isEmpty
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.secondary))
          : CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(child: _HeroBanner(itemsInCart: itemsInCart)),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: _QuickActions()),
                const SliverToBoxAdapter(child: SizedBox(height: 18)),
                const SliverToBoxAdapter(child: _SectionTitle(title: 'Nearby stores', subtitle: 'Hand-picked for fast flights')),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  sliver: SliverList.separated(
                    itemCount: stores.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (context, index) {
                      final store = stores[index];
                      final products = appState.productsForStore(store.id);
                      return _StoreSection(
                        store: store,
                        products: products,
                        isSelected: appState.selectedStore?.id == store.id,
                        onSelectStore: () async {
                          final switched = await context.read<AppState>().selectStore(store);
                          if (switched && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Store switched. Your cart was cleared to avoid mix-ups.'),
                                backgroundColor: theme.colorScheme.surface,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.colorScheme.secondary.withOpacity(0.4)),
                                ),
                              ),
                            );
                          }
                        },
                        onAdd: (product) => context.read<AppState>().addToCart(product),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final int itemsInCart;

  const _HeroBanner({required this.itemsInCart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE3D5), Color(0xFFF6F2EC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -10,
              child: _Halo(size: 120, color: theme.colorScheme.secondary.withOpacity(0.15)),
            ),
            Positioned(
              right: 30,
              top: 50,
              child: _Halo(size: 60, color: theme.colorScheme.primary.withOpacity(0.12)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'FAST DELIVERY',
                        style: GoogleFonts.sora(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: theme.colorScheme.onSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (itemsInCart > 0)
                      Text(
                        '$itemsInCart item${itemsInCart == 1 ? '' : 's'} ready to fly',
                        style: TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.7)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Launch a store to your doorstep.',
                  style: GoogleFonts.sora(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onBackground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Curated essentials, real-time drone tracking, and clean delivery in under 20 minutes.',
                  style: TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.7), height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen()));
                      },
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: const Text('Start order'),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'No delivery fees today',
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _MetricPill(label: 'Live tracking'),
                    _MetricPill(label: 'Insulated payload'),
                    _MetricPill(label: 'KZT pricing'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  final double size;
  final Color color;

  const _Halo({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: const [
          Expanded(
            child: _ActionCard(
              icon: Icons.bolt_rounded,
              title: 'Express',
              subtitle: '15-20 min',
              tone: Color(0xFF0B3C49),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _ActionCard(
              icon: Icons.favorite_rounded,
              title: 'Top picks',
              subtitle: 'Best sellers',
              tone: Color(0xFF7C2D12),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _ActionCard(
              icon: Icons.wallet_rounded,
              title: 'Deals',
              subtitle: 'Save today',
              tone: Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: tone.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.sora(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;

  const _MetricPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StoreSection extends StatelessWidget {
  final Store store;
  final List<Product> products;
  final bool isSelected;
  final VoidCallback onSelectStore;
  final ValueChanged<Product> onAdd;

  const _StoreSection({
    required this.store,
    required this.products,
    required this.isSelected,
    required this.onSelectStore,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.storefront, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      store.address,
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: const [
                        _InfoChip(label: 'Prep 6-12 min', icon: Icons.timer_outlined),
                        SizedBox(width: 6),
                        _InfoChip(label: '4.9 rating', icon: Icons.star_rounded),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSelectStore,
                style: FilledButton.styleFrom(
                  backgroundColor: isSelected ? const Color(0xFF0F766E) : theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: Text(isSelected ? 'Selected' : 'Choose'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: products.isEmpty
                ? Center(
                    child: Text('No items yet. Check back soon.', style: theme.textTheme.bodySmall),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final product = products[i];
                      return _ProductCard(
                        product: product,
                        width: 180,
                        onAdd: () => onAdd(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final double width;
  final VoidCallback onAdd;

  const _ProductCard({
    required this.product,
    required this.onAdd,
    this.width = 180,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      product.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) => Container(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        child: Center(
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                      ),
                      child: Text(
                        'Popular',
                        style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sora(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.3,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'KZT ${product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.sora(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(product.weight / 1000).toStringAsFixed(1)} kg',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('Quick add'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.background, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.secondary.withOpacity(0.5),
            blurRadius: 5,
          )
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.sora(
          color: theme.colorScheme.onSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
