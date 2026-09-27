import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:web_socket_channel/web_socket_channel.dart' show WebSocketChannel;

import 'api_client.dart';
import 'config.dart';
import 'ws_connector.dart';

/// Realtime feed from the backend. Flutter never polls: every number on screen
/// arrives from a REST snapshot or from one of these events.
class WsClient {
  WsClient({required this.api});

  final ApiClient api;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnect;
  bool _disposed = false;
  int _attempt = 0;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _connection = ValueNotifier<WsStatus>(WsStatus.connecting);

  /// Typed events: bot_state, pnl_update, position_update, trade, opportunity,
  /// ai_log, risk_alert, error, state.
  Stream<Map<String, dynamic>> get events => _events.stream;
  ValueListenable<WsStatus> get connection => _connection;
  WsStatus get status => _connection.value;
  bool get isConnected => _connection.value == WsStatus.connected;

  void connect() {
    if (_disposed) return;
    _reconnect?.cancel();
    _teardown();
    _connection.value = WsStatus.connecting;

    final base = AppConfig.wsBaseUrl;
    final token = api.token;
    if (token == null) {
      // Never open an unauthenticated socket: the backend answers 403 and the
      // reconnect loop would spin forever.
      _scheduleReconnect();
      return;
    }
    final query = '?token=${Uri.encodeComponent(token)}';
    try {
      final channel = connectSocket(Uri.parse('$base/ws/stream$query'));
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (Object error) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    _attempt = 0;
    _connection.value = WsStatus.connected;
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) _events.add(decoded);
    } catch (_) {
      // Ignore non-JSON frames.
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _teardown();
    _connection.value = WsStatus.reconnecting;
    // Backoff 1s, 2s, 4s ... capped at 20s.
    final seconds = (1 << _attempt.clamp(0, 4)).clamp(1, 20);
    _attempt++;
    _reconnect = Timer(Duration(seconds: seconds), connect);
  }

  /// Exposed for tests that assert malformed frames never reach the UI.
  @visibleForTesting
  void handleFrameForTest(dynamic raw) => _onMessage(raw);

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _teardown();
    _events.close();
    _connection.dispose();
  }
}

enum WsStatus { connecting, connected, reconnecting, offline }
