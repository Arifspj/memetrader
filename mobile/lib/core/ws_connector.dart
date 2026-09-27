/// Opens a WebSocket with the implementation that matches the platform.
///
/// `web_socket_channel/web_socket_channel.dart` exports a runtime *adapter*.
/// On the web that adapter signals a failed handshake through an un-awaited
/// completer, so the error escapes as an uncaught Flutter exception instead of
/// reaching the caller's reconnect logic. Binding the implementation at compile
/// time keeps the failure on the channel stream, where `WsClient` already
/// handles it and retries with backoff.
library;

export 'ws_connector_io.dart'
    if (dart.library.js_interop) 'ws_connector_web.dart';
