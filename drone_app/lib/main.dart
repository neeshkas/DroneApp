import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/catalog_screen.dart';
import 'state/app_state.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Sales-focused, clean light theme
    const ink = Color(0xFF0F172A);
    const ocean = Color(0xFF0B3C49);
    const sun = Color(0xFFFF6B35);
    const sand = Color(0xFFF6F2EC);
    const surface = Color(0xFFFFFFFF);
    const outline = Color(0xFFE5DDD2);

    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'Drone Delivery',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: ocean,
            secondary: sun,
            background: sand,
            surface: surface,
            onPrimary: sand,
            onSecondary: ink,
            onBackground: ink,
            onSurface: ink,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: sand,
          textTheme: GoogleFonts.soraTextTheme(
            Theme.of(context).textTheme.apply(
                  displayColor: ink,
                  bodyColor: ink.withOpacity(0.8),
                ),
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            titleTextStyle: GoogleFonts.sora(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: ink,
            ),
          ),
          cardTheme: CardThemeData(
            color: surface,
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: outline, width: 1),
            ),
            shadowColor: Colors.black.withOpacity(0.06),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: ocean,
              foregroundColor: sand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              textStyle: GoogleFonts.sora(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 0.2,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ocean, width: 1.5),
            ),
            hintStyle: TextStyle(color: ink.withOpacity(0.4)),
            prefixIconColor: ink.withOpacity(0.5),
          ),
        ),
        home: const CatalogScreen(),
      ),
    );
  }
}
