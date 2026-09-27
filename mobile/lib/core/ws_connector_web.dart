import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_connector_io.dart' show absorbReadyError;

/// Browser socket on the web.
WebSocketChannel connectSocket(Uri uri) {
  final channel = HtmlWebSocketChannel.connect(uri);
  // See absorbReadyError: the adapter's un-awaited `ready` completer would
  // otherwise turn every failed reconnect into an uncaught Flutter error.
  absorbReadyError(channel, channel.ready);
  return channel;
}
