import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/store.dart';
import '../state/app_state.dart';
import '../widgets/animated_button.dart';

class CatalogScreen extends StatelessWidget {
  final VoidCallback onOpenCart;
  const CatalogScreen({super.key, required this.onOpenCart});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final itemsInCart = appState.cartItems.fold<int>(0, (sum, item) => sum + item.quantity);
    final stores = appState.stores;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DroneDelivery'),
        actions: [
          IconButton(
            onPressed: onOpenCart,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined),
                if (itemsInCart > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: _Badge(label: itemsInCart.toString()),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: stores.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: stores.length,
              itemBuilder: (context, index) {
                final store = stores[index];
                final products = appState.productsForStore(store.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _StoreSection(
                    store: store,
                    products: products,
                    isSelected: appState.selectedStore?.id == store.id,
                    onSelectStore: () async {
                      final switched = await context.read<AppState>().selectStore(store);
                      if (switched) {
                        // Покажем уведомление, что корзина очищена
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Корзина очищена: выбран другой магазин')),
                          );
                        }
                      }
                    },
                    onAdd: (product) => context.read<AppState>().addToCart(product),
                  ),
                );
              },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(store.address, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
              ],
            ),
            AnimatedButton(
              onPressed: onSelectStore,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(Icons.check_circle, size: 16),
                    const SizedBox(width: 4),
                  ],
                  Text(isSelected ? 'Выбрано' : 'Выбрать'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 290,
          child: products.isEmpty
              ? const Center(child: Text('Товары загружаются...'))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final product = products[i];
                    return _ProductCard(
                      title: product.title,
                      price: product.price,
                      weight: product.weight,
                      imageUrl: product.imageUrl,
                      width: 170,
                      onAdd: () => onAdd(product),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatefulWidget {
  final String title;
  final double price;
  final double weight;
  final String imageUrl;
  final double width;
  final VoidCallback onAdd;

  const _ProductCard({
    required this.title,
    required this.price,
    required this.weight,
    required this.imageUrl,
    required this.onAdd,
    this.width = 180,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
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
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey.shade50],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? Colors.blue.shade200 : Colors.grey.shade200,
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? const Color(0x22000000) : const Color(0x11000000),
                blurRadius: _isHovered ? 15 : 10,
                offset: Offset(0, _isHovered ? 8 : 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 140,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Stack(
                    children: [
                      Image.network(
                        widget.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, __) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.blue.shade100, Colors.purple.shade100],
                            ),
                          ),
                          child: Center(
                            child: Icon(Icons.shopping_bag, size: 48, color: Colors.white.withOpacity(0.8)),
                          ),
                        ),
                      ),
                      if (_isHovered)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.1),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.2,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      '₸${widget.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(widget.weight / 1000).toStringAsFixed(1)} кг',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: AnimatedButton(
                    onPressed: widget.onAdd,
                    child: const Text('В корзину'),
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

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
