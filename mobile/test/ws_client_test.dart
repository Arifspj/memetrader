import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memetrader_app/core/api_client.dart';
import 'package:memetrader_app/core/ws_client.dart';

/// The socket must never open without a token: the backend answers an
/// unauthenticated `/ws/stream` with 403, and retrying forever would spin.
void main() {
  test('connect() with no token falls back to the reconnect path', () async {
    final ws = WsClient(api: ApiClient());
    ws.connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      ws.status,
      WsStatus.reconnecting,
      reason: 'no token means no socket, but a scheduled retry',
    );
    expect(ws.isConnected, isFalse);
    ws.dispose();
  });

  test('a failing connect never escapes as an unhandled async error', () async {
    // No server is listening in the test zone, so this connect is guaranteed to
    // fail. It must land in the reconnect path rather than the zone's unhandled
    // error handler (which is what the old adapter did on every reconnect).
    final ws = WsClient(api: ApiClient()..token = 'jwt-abc');
    var unhandled = 0;
    final zone = Zone.current.fork(specification: ZoneSpecification(
      handleUncaughtError: (_, __, ___, error, ____) {
        unhandled += 1;
      },
    ));
    zone.run(() {
      ws.connect();
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(unhandled, 0, reason: 'connect failure must be caught by WsClient');
    expect(ws.isConnected, isFalse);
    ws.dispose();
  });

  test('malformed frames are ignored, JSON objects are forwarded', () async {
    final ws = WsClient(api: ApiClient()..token = 'jwt-abc');
    final events = <Map<String, dynamic>>[];
    final sub = ws.events.listen(events.add);

    ws.handleFrameForTest('not json at all');
    ws.handleFrameForTest('[1,2,3]');
    ws.handleFrameForTest(42);
    ws.handleFrameForTest('{"type":"state","data":{}}');
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 1);
    expect(events.single['type'], 'state');
    await sub.cancel();
    ws.dispose();
  });
}
