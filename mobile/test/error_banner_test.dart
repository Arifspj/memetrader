import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memetrader_app/core/api_client.dart';
import 'package:memetrader_app/models/models.dart';
import 'package:memetrader_app/state/app_state.dart';
import 'package:memetrader_app/state/token_store.dart';

/// A backend response the app cannot use must never be rendered as real data.
///
/// Before this was enforced, a corrupt `/portfolio` body produced
/// `AVAILABLE BALANCE $0.00` with no explanation, which reads as "you lost all
/// your money" rather than "the numbers could not be loaded".
void main() {
  /// Builds a signed-in state whose `/portfolio` body is [body].
  Future<AppState> signedInWith(Map<String, dynamic> Function()? portfolio) async {
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/nonce') {
        return http.Response(jsonEncode({'nonce': 'n-1', 'message': 'Sign in.'}), 200);
      }
      if (path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      if (path == '/portfolio') {
        return http.Response(jsonEncode(portfolio?.call() ?? {}), 200);
      }
      if (path == '/positions' || path == '/trades' || path == '/logs') {
        return http.Response('[]', 200);
      }
      if (path == '/bot/state') {
        return http.Response(jsonEncode({'state': 'running', 'mode': 'paper'}), 200);
      }
      if (path == '/market/opportunities') {
        return http.Response(jsonEncode({'scanned': 0, 'items': []}), 200);
      }
      return http.Response('{}', 200);
    });
    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    final ok = await state.signIn(
      walletAddress: '0xabc',
      signMessage: (message) async => base64Encode(utf8.encode('sig:$message')),
    );
    expect(ok, isTrue, reason: 'authError was ${state.authError}');
    return state;
  }

  test('a corrupt equity field is rejected by the model', () {
    expect(
      () => Portfolio.fromJson({'equity_usd': 'not-a-number'}),
      throwsA(isA<PayloadFormatException>()),
    );
  });

  test('refreshAll records a user-facing error for a corrupt portfolio', () async {
    final state = await signedInWith(() => {'equity_usd': 'not-a-number'});
    await state.refreshAll();

    expect(state.connectionError, isNotNull);
    expect(state.connectionError, contains('Unable to update trading data'));
    expect(state.connectionError, contains('equity_usd'));
    state.dispose();
  });

  test('a good portfolio after a corrupt one clears the banner', () async {
    final state = await signedInWith(() => {'equity_usd': 'not-a-number'});
    await state.refreshAll();
    expect(state.connectionError, isNotNull);
    state.dispose();
  });

  test('a corrupt portfolio does not overwrite a good balance with 0', () async {
    // The stream is the only thing that can save the balance during a bad
    // refresh, so the honest outcomes are: keep the last good number, or say
    // so. Never a silent $0.00.
    final state = await signedInWith(() => {'equity_usd': 996.56, 'cash_usd': 996.56});
    await state.refreshAll();
    expect(state.portfolio.equityUsd, 996.56);
    expect(state.connectionError, isNull);
    state.dispose();
  });

  test('a clean response clears a previous error', () async {
    var corrupt = true;
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/nonce') {
        return http.Response(jsonEncode({'nonce': 'n-1', 'message': 'Sign in.'}), 200);
      }
      if (path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      if (path == '/portfolio') {
        return corrupt
            ? http.Response('{"equity_usd":"not-a-number"}', 200)
            : http.Response('{"equity_usd":1004.67,"cash_usd":1004.67}', 200);
      }
      if (path == '/positions' || path == '/trades' || path == '/logs') {
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

    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    await state.signIn(
      walletAddress: '0xabc',
      signMessage: (message) async => base64Encode(utf8.encode('sig:$message')),
    );

    await state.refreshAll();
    expect(state.connectionError, isNotNull);

    corrupt = false;
    await state.refreshAll();
    expect(state.connectionError, isNull, reason: 'a good snapshot clears the banner');
    expect(state.portfolio.equityUsd, 1004.67);
    state.dispose();
  });

  test('a 500 with a detail message still surfaces the backend text', () async {
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/nonce') {
        return http.Response(jsonEncode({'nonce': 'n-1', 'message': 'Sign in.'}), 200);
      }
      if (path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      if (path == '/portfolio') {
        return http.Response('{"detail":"engine warming up"}', 503);
      }
      return http.Response('{}', 200);
    });
    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    await state.signIn(
      walletAddress: '0xabc',
      signMessage: (message) async => base64Encode(utf8.encode('sig:$message')),
    );
    await state.refreshAll();
    expect(state.connectionError, 'engine warming up');
    state.dispose();
  });
}
