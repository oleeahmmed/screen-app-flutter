import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Normalize ws/wss [Uri] — Windows dart:io rejects implicit `:0` ports.
Uri normalizeWsUri(Uri uri) {
  final secure = uri.scheme == 'wss' || uri.scheme == 'https';
  final scheme = secure ? 'wss' : 'ws';
  const defaultPort = 443;
  const defaultPortInsecure = 80;
  final expectedDefault = secure ? defaultPort : defaultPortInsecure;

  var port = uri.hasPort ? uri.port : expectedDefault;
  if (port <= 0) {
    port = expectedDefault;
  }

  if (port == expectedDefault) {
    return Uri(
      scheme: scheme,
      host: uri.host,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    );
  }

  return Uri(
    scheme: scheme,
    host: uri.host,
    port: port,
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
  );
}

/// Native WebSocket connect using explicit ws/wss [Uri] (avoids https://:0 on Windows).
WebSocketChannel connectWs(String url) =>
    IOWebSocketChannel.connect(normalizeWsUri(Uri.parse(url)));

WebSocketChannel connectWsUri(Uri uri) =>
    IOWebSocketChannel.connect(normalizeWsUri(uri));
