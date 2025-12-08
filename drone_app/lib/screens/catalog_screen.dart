import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/store.dart';
import '../state/app_state.dart';

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
            FilledButton.tonal(
              onPressed: onSelectStore,
              child: Text(isSelected ? 'Выбрано' : 'Выбрать'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 270,
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

class _ProductCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 140,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.image_not_supported_outlined)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('₸${price.toStringAsFixed(0)} · ${(weight / 1000).toStringAsFixed(1)} кг',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAdd,
                child: const Text('В корзину'),
              ),
            ),
          ),
        ],
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
