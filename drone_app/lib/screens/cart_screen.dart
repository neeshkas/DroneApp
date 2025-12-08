import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class CartScreen extends StatelessWidget {
  final VoidCallback onOpenCheckout;
  const CartScreen({super.key, required this.onOpenCheckout});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final items = appState.cartItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Корзина')),
      body: SafeArea(
        child: Column(
        children: [
          if (items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Корзина пуста'),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('₸${item.product.price.toStringAsFixed(0)} · ${(item.product.weight / 1000).toStringAsFixed(1)} кг',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.grey.shade700)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => context.read<AppState>().decrement(item.product.id),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(item.quantity.toString(), style: Theme.of(context).textTheme.titleMedium),
                            IconButton(
                              onPressed: () => context.read<AppState>().increment(item.product.id),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          _CartSummary(
            total: appState.totalPrice,
            totalWeight: appState.totalWeight,
            isOverweight: appState.isOverweight,
            isDisabled: items.isEmpty || appState.isOverweight,
            onCheckout: onOpenCheckout,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, -4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Итого'),
              Text('₸${total.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Общий вес'),
              Text('${totalWeight.toStringAsFixed(0)} г'),
            ],
          ),
          if (isOverweight)
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isDisabled ? null : onCheckout,
              child: const Text('Оформить'),
            ),
          ),
        ],
      ),
    );
  }
}
