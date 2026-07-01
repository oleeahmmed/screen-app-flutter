import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native WebSocket connect using explicit ws/wss URL (avoids https://:0 on Windows).
WebSocketChannel connectWs(String url) => IOWebSocketChannel.connect(url);
