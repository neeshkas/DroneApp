import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/cart_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/tracking_screen.dart';
import 'state/app_state.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.black;
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'DroneDelivery',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: baseColor, brightness: Brightness.light),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: baseColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        home: const _HomeShell(),
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int index = 0;

  void _goTo(int newIndex) => setState(() => index = newIndex);

  @override
  Widget build(BuildContext context) {
    final screens = [
      CatalogScreen(onOpenCart: () => _goTo(1)),
      CartScreen(onOpenCheckout: () => _goTo(2)),
      CheckoutScreen(onStartTracking: () => _goTo(3)),
      const TrackingScreen(),
    ];

    return Scaffold(
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Каталог'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'Корзина'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Оформление'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Трекинг'),
        ],
      ),
    );
  }
}
