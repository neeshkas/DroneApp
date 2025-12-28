// LocalDb is currently unused.
// All data is fetched from backend via REST API and WebSocket.
// This file is kept for future local caching if needed.

class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();

  Future<void> init() async {
    // No initialization needed - all data comes from backend
  }
}
