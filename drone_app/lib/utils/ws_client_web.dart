import 'dart:async';
import 'dart:html' as html;

class WsClient {
  final html.WebSocket _socket;
  final StreamController<String> _controller = StreamController.broadcast();

  WsClient._(this._socket) {
    _socket.onMessage.listen((event) {
      final data = event.data;
      _controller.add(data is String ? data : data.toString());
    });
    _socket.onError.listen((event) {
      _controller.addError(event);
    });
    _socket.onClose.listen((_) {
      _controller.close();
    });
  }

  static Future<WsClient> connect(String url) {
    final socket = html.WebSocket(url);
    final completer = Completer<WsClient>();

    socket.onOpen.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete(WsClient._(socket));
      }
    });
    socket.onError.first.then((event) {
      if (!completer.isCompleted) {
        completer.completeError(event);
      }
    });

    return completer.future;
  }

  Stream<String> get stream => _controller.stream;

  void send(String message) {
    _socket.send(message);
  }

  void close() {
    _socket.close();
  }
}
