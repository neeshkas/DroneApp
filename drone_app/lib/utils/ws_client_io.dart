import 'dart:async';
import 'dart:io';

class WsClient {
  final WebSocket _socket;
  final StreamController<String> _controller = StreamController.broadcast();

  WsClient._(this._socket) {
    _socket.listen(
      (data) {
        _controller.add(data is String ? data : data.toString());
      },
      onError: (error) {
        _controller.addError(error);
      },
      onDone: () {
        _controller.close();
      },
    );
  }

  static Future<WsClient> connect(String url) async {
    final socket = await WebSocket.connect(url);
    return WsClient._(socket);
  }

  Stream<String> get stream => _controller.stream;

  void send(String message) {
    _socket.add(message);
  }

  void close() {
    _socket.close();
  }
}
