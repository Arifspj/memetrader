import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memetrader_app/core/api_client.dart';
import 'package:memetrader_app/state/app_state.dart';
import 'package:memetrader_app/state/token_store.dart';

/// The socket only reports how many positions are open, so the app refetches
/// the real list whenever that count moves. Those refetches are fire-and-forget
/// and overlap while the engine trades; if a slow older response is allowed to
/// land last, the screen keeps showing a position count the backend no longer
/// has, and nothing refetches it until the count moves again.
void main() {
  Map<String, dynamic> posJson(String id, {String status = 'open'}) => {
        'id': id,
        'symbol': 'TOK$id',
        'name': 'Token $id',
        'mint': 'mint-$id',
        'status': status,
        'qty': 1,
        'entry_price': 0.001,
        'current_price': 0.001,
        'invested_usd': 10,
        'entry_score': 60,
        'stop_loss': 0.0009,
        'take_profit': 0.0011,
        'trailing_stop': 0.00095,
        'unrealized_pnl_usd': 0,
        'unrealized_pnl_pct': 0,
        'opened_at': '2026-01-01T00:00:00Z',
        'closed_at': status == 'closed' ? '2026-01-01T01:00:00Z' : null,
        'closed_price': status == 'closed' ? 0.001 : null,
        'realized_pnl_usd': status == 'closed' ? 1 : null,
      };

  String listBody(List<String> ids, String status) =>
      jsonEncode([for (final id in ids) posJson(id, status: status)]);

  /// A backend whose open-position list is controlled by the test, with a
  /// per-call delay so one response can be made to arrive after a newer one.
  /// `allPositions()` asks for open and closed separately, so each is handled
  /// on its own.
  MockClient server({
    required List<String> Function() openIds,
    int Function(int positionCount)? delayFor,
  }) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/nonce') {
        return http.Response(jsonEncode({'nonce': 'n-1', 'message': 'Sign in.'}), 200);
      }
      if (path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      if (path == '/portfolio') {
        return http.Response('{"equity_usd":1000,"cash_usd":1000}', 200);
      }
      if (path == '/positions') {
        final open = request.url.queryParameters['status'] != 'closed';
        // Snapshot the payload now, then delay the response. This is what makes
        // an in-flight request carry stale data. The delay is keyed on the
        // payload so the bigger (older) snapshot is always the slow one,
        // whatever order the requests actually reach the server in.
        final ids = open ? openIds() : const <String>[];
        final delay = delayFor == null ? 0 : delayFor(ids.length);
        await Future<void>.delayed(Duration(milliseconds: delay));
        return http.Response(listBody(ids, open ? 'open' : 'closed'), 200);
      }
      if (path == '/trades' || path == '/logs') {
        return http.Response('[]', 200);
      }
      if (path == '/bot/state') {
        return http.Response('{"state":"running","mode":"paper"}', 200);
      }
      if (path == '/market/opportunities') {
        return http.Response('{"scanned":0,"items":[]}', 200);
      }
      return http.Response('{}', 200);
    });
  }

  Future<AppState> signedIn(MockClient mock) async {
    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    await state.signIn(
      walletAddress: '0xabc',
      signMessage: (message) async => base64Encode(utf8.encode('sig:$message')),
    );
    return state;
  }

  test('a slow older refetch cannot overwrite the newest position list', () async {
    // The engine opens 3 positions, a refetch starts and is slow, then the
    // positions are flattened to 1 and a newer refetch returns first. Without a
    // guard the slow 3-position response lands last and sticks, and nothing
    // refetches it because the streamed count has not moved again.
    var ids = <String>[];
    final mock = server(
      openIds: () => ids,
      // The 3-position snapshot is the slow one, the 1-position one is fast.
      delayFor: (n) => (n == 3 ? 300 : 5),
    );
    final state = await signedIn(mock);
    await state.refreshAll();
    expect(state.openPositions.length, 0);

    ids = ['a', 'b', 'c'];
    state.debugRefreshTradeLists(); // captures 3, resolves slowly
    // Let the request reach the server and snapshot the 3 positions before
    // changing what the backend reports.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    ids = ['a'];
    state.debugRefreshTradeLists(); // captures 1, resolves fast

    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(
      state.openPositions.length,
      1,
      reason: 'the newer refetch must win even though an older one finished later',
    );
    state.dispose();
  });

  test('refetches that resolve in order still apply', () async {
    var ids = <String>['a'];
    final mock = server(openIds: () => ids, delayFor: (_) => 5);    final state = await signedIn(mock);
    await state.refreshAll();
    expect(state.openPositions.length, 1);

    ids = ['a', 'b'];
    state.debugRefreshTradeLists();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(state.openPositions.length, 2, reason: 'a newer snapshot must be applied');
    state.dispose();
  });

  test('a failed list refetch keeps the last good list', () async {
    var fail = false;
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/nonce') {
        return http.Response(jsonEncode({'nonce': 'n-1', 'message': 'Sign in.'}), 200);
      }
      if (path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      if (path == '/portfolio') {
        return http.Response('{"equity_usd":1000,"cash_usd":1000}', 200);
      }
      if (path == '/positions') {
        final open = request.url.queryParameters['status'] != 'closed';
        if (fail) return http.Response('{"detail":"boom"}', 500);
        return http.Response(listBody(open ? ['a'] : [], open ? 'open' : 'closed'), 200);
      }
      if (path == '/trades' || path == '/logs') {
        return http.Response('[]', 200);
      }
      if (path == '/bot/state') {
        return http.Response('{"state":"running","mode":"paper"}', 200);
      }
      if (path == '/market/opportunities') {
        return http.Response('{"scanned":0,"items":[]}', 200);
      }
      return http.Response('{}', 200);
    });
    final state = await signedIn(mock);
    await state.refreshAll();
    expect(state.openPositions.length, 1);

    fail = true;
    state.debugRefreshTradeLists();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(state.openPositions.length, 1, reason: 'a failed refresh must not blank the list');
    state.dispose();
  });
}
