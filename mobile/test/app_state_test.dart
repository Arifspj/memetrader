import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memetrader_app/core/api_client.dart';
import 'package:memetrader_app/state/app_state.dart';
import 'package:memetrader_app/state/token_store.dart';

/// Guards the wiring between AppState, ApiClient, WsClient and TokenStore.
///
/// The socket authenticates by reading the JWT straight off the ApiClient, so
/// if those two ever stop being the same object the app looks fine but
/// `/ws/stream?token=` goes out empty and the backend answers 403. That is
/// exactly the bug this file exists to prevent.
void main() {
  const address = 'So11111111111111111111111111111111111111112';

  Future<AppState> signedInState({TokenStore? store}) async {
    final mock = MockClient((request) async {
      if (request.url.path == '/auth/nonce') {
        return http.Response(
          jsonEncode({'nonce': 'n-1', 'message': 'Sign in to AI Meme Trader.'}),
          200,
        );
      }
      if (request.url.path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      return http.Response('{}', 200);
    });
    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: store ?? InMemoryTokenStore(),
    );
    final ok = await state.signIn(
      walletAddress: address,
      signMessage: (message) async => base64Encode(utf8.encode('sig:$message')),
    );
    expect(ok, isTrue, reason: 'authError was ${state.authError}');
    return state;
  }

  test('AppState and its WsClient share one ApiClient', () {
    final state = AppState(store: InMemoryTokenStore());
    // The socket must be able to see a token set through the state.
    state.api.token = 'jwt-shared';
    expect(state.socket.api, same(state.api));
    expect(state.socket.api.token, 'jwt-shared');
    state.dispose();
  });

  test('an injected ApiClient is the one the socket sees', () {
    final mock = MockClient((_) async => http.Response('{}', 200));
    final api = ApiClient(client: mock, baseUrl: 'http://test.local');
    final state = AppState(api: api, store: InMemoryTokenStore());
    expect(state.socket.api, same(api));
    state.dispose();
  });

  test('sign-in stores the JWT where the socket can read it', () async {
    var seenAuthHeader = '<none>';
    final mock = MockClient((request) async {
      if (request.url.path == '/auth/nonce') {
        return http.Response(
          jsonEncode({'nonce': 'n-1', 'message': 'Sign in to AI Meme Trader.'}),
          200,
        );
      }
      if (request.url.path == '/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt-real'}), 200);
      }
      seenAuthHeader = request.headers['Authorization'] ?? '<none>';
      return http.Response('{}', 200);
    });

    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    final ok = await state.signIn(
      walletAddress: address,
      signMessage: (message) async => base64Encode(utf8.encode('sig:$message')),
    );

    expect(ok, isTrue, reason: 'authError was ${state.authError}');
    expect(state.isSignedIn, isTrue);
    expect(state.api.token, 'jwt-real');
    expect(state.socket.api.token, 'jwt-real');
    expect(seenAuthHeader, 'Bearer jwt-real');
    state.dispose();
  });

  test('sign-in surfaces a backend rejection as a signed-out state', () async {
    final mock = MockClient((request) async {
      if (request.url.path == '/auth/nonce') {
        return http.Response(jsonEncode({'nonce': 'n', 'message': 'm'}), 200);
      }
      return http.Response(jsonEncode({'detail': 'signature verification failed'}), 401);
    });

    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    final ok = await state.signIn(
      walletAddress: address,
      signMessage: (_) async => base64Encode(utf8.encode('bad-sig')),
    );

    expect(ok, isFalse);
    expect(state.isSignedIn, isFalse);
    expect(state.authError, 'signature verification failed');
    state.dispose();
  });

  test('signOut clears the token the socket would have used', () async {
    final state = await signedInState();
    expect(state.api.token, 'jwt-real');

    await state.signOut();
    expect(state.api.token, isNull);
    expect(state.isSignedIn, isFalse);
    state.dispose();
  });

  test('restoreSession brings back the same address and token', () async {
    final store = InMemoryTokenStore();
    final first = await signedInState(store: store);
    final addressOut = first.walletAddress;
    first.dispose();

    // Second launch reads only from the store, exactly like a browser refresh.
    final mock = MockClient((_) async => http.Response('{}', 200));
    final state = AppState(
      api: ApiClient(client: mock, baseUrl: 'http://test.local'),
      store: store,
    );
    final restored = await state.restoreSession();

    expect(restored, isTrue);
    expect(state.walletAddress, addressOut);
    expect(state.api.token, 'jwt-real');
    expect(state.socket.api.token, 'jwt-real');
    state.dispose();
  });

  test('restoreSession refuses a store with no token', () async {
    final state = AppState(
      api: ApiClient(client: MockClient((_) async => http.Response('{}', 200)),
          baseUrl: 'http://test.local'),
      store: InMemoryTokenStore(),
    );
    expect(await state.restoreSession(), isFalse);
    expect(state.isSignedIn, isFalse);
    state.dispose();
  });
}
