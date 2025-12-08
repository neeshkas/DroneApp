import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../models/store.dart';

class LocalDb {
  static const _dbName = 'drone_app.db';
  static const _dbVersion = 1;

  static final LocalDb instance = LocalDb._();
  Database? _db;

  LocalDb._();

  Future<void> init() async {
    if (kIsWeb) return; // sqflite не работает в вебе
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stores(
            id TEXT PRIMARY KEY,
            name TEXT,
            address TEXT,
            latitude REAL,
            longitude REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE products(
            id TEXT PRIMARY KEY,
            store_id TEXT,
            title TEXT,
            price REAL,
            weight REAL,
            image_url TEXT
          )
        ''');
      },
    );
    await _seed();
  }

  Future<void> _seed() async {
    if (kIsWeb) return;
    final existing = await _db!.query('stores', limit: 1);
    if (existing.isNotEmpty) return;

    final stores = _sampleStores;
    final products = _sampleProducts;

    final batch = _db!.batch();
    for (final s in stores) {
      batch.insert('stores', {
        'id': s.id,
        'name': s.name,
        'address': s.address,
        'latitude': s.latitude,
        'longitude': s.longitude,
      });
    }
    for (final p in products) {
      batch.insert('products', {
        'id': p.id,
        'store_id': p.storeId,
        'title': p.title,
        'price': p.price,
        'weight': p.weight,
        'image_url': p.imageUrl,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Store>> getStores() async {
    if (kIsWeb) return _sampleStores;
    final rows = await _db!.query('stores');
    return rows
        .map((r) => Store(
              id: r['id'] as String,
              name: r['name'] as String,
              address: r['address'] as String,
              latitude: r['latitude'] as double,
              longitude: r['longitude'] as double,
            ))
        .toList();
  }

  Future<List<Product>> getProductsByStore(String storeId) async {
    if (kIsWeb) {
      return _sampleProducts.where((p) => p.storeId == storeId).toList();
    }
    final rows = await _db!.query('products', where: 'store_id = ?', whereArgs: [storeId]);
    return rows
        .map((r) => Product(
              id: r['id'] as String,
              storeId: r['store_id'] as String,
              title: r['title'] as String,
              price: r['price'] as double,
              weight: r['weight'] as double,
              imageUrl: r['image_url'] as String,
            ))
        .toList();
  }

  // Статичные данные на случай веба и для первичного наполнения
  List<Store> get _sampleStores {
    return List.generate(10, (i) {
      final baseLat = 43.235 + i * 0.002;
      final baseLng = 76.88 + i * 0.003;
      return Store(
        id: 's${i + 1}',
        name: 'Магазин ${i + 1}',
        address: 'Алматы, проспект Абая ${(50 + i)}',
        latitude: baseLat,
        longitude: baseLng,
      );
    });
  }

  List<Product> get _sampleProducts {
    final stores = _sampleStores;
    final List<Product> result = [];
    for (final store in stores) {
      for (int i = 0; i < 10; i++) {
        result.add(Product(
          id: '${store.id}_p${i + 1}',
          storeId: store.id,
          title: 'Товар ${i + 1} · ${store.name}',
          price: 1500 + (i * 150),
          weight: 200 + i * 30,
          imageUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=400&q=60',
        ));
      }
    }
    return result;
  }
}
