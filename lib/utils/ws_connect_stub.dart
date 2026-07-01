import 'package:web_socket_channel/web_socket_channel.dart';

/// Web builds have no dart:io WebSocket — connect is unused on web in this app.
WebSocketChannel connectWs(String url) {
  throw UnsupportedError('WebSocket is not supported on this platform');
}
