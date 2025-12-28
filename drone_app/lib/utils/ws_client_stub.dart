import 'dart:async';

class WsClient {
  static Future<WsClient> connect(String url) {
    return Future.error(UnsupportedError('WebSocket not supported on this platform.'));
  }

  Stream<String> get stream => const Stream.empty();

  void send(String message) {}

  void close() {}
}
