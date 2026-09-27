import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native socket on the VM and in tests.
WebSocketChannel connectSocket(Uri uri) {
  final channel = IOWebSocketChannel.connect(uri);
  absorbReadyError(channel, channel.ready);
  return channel;
}

/// `web_socket_channel` 3.x reports a failed handshake twice: once on the
/// channel stream, which [WsClient] handles, and once on an internal `ready`
/// future that nobody awaits. The second copy escapes as an unhandled
/// asynchronous error and crashes the zone, so it is absorbed here and the
/// stream copy stays the single source of truth for reconnecting.
void absorbReadyError(WebSocketChannel channel, Future<void> ready) {
  unawaited(ready.then((_) {}, onError: (Object _) {}));
}
