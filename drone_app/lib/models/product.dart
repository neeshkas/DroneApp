class Product {
  final String id;
  final String storeId;
  final String title;
  final double price;
  final double weight; // grams
  final String imageUrl;

  const Product({
    required this.id,
    required this.storeId,
    required this.title,
    required this.price,
    required this.weight,
    required this.imageUrl,
  });
}
