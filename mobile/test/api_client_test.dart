import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memetrader_app/core/api_client.dart';

/// Every request is answered by a fake so the contract is verified without a
/// running backend. This is what catches backend/Flutter JSON drift.
void main() {
  late List<Uri> requested;
  late List<http.Request> sent;

  ApiClient clientReturning(
    Object body, {
    int status = 200,
  }) {
    final mock = MockClient((request) async {
      requested.add(request.url);
      sent.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return ApiClient(client: mock, baseUrl: 'http://test.local');
  }

  setUp(() {
    requested = <Uri>[];
    sent = <http.Request>[];
  });

  group('contract: paths', () {
    test('portfolio hits /portfolio', () async {
      final api = clientReturning(const {'equity_usd': 1000, 'cash_usd': 900});
      final portfolio = await api.portfolio();
      expect(requested.single.path, '/portfolio');
      expect(portfolio.equityUsd, 1000);
    });

    test('bot state hits /bot/state, not /bot/status', () async {
      final api = clientReturning(const {'state': 'running', 'tokens_scanned': 143});
      final status = await api.botState();
      expect(requested.single.path, '/bot/state');
      expect(status.tokensScanned, 143);
    });

    test('opportunities hit /market/opportunities with a limit', () async {
      final api = clientReturning(const {'scanned': 47, 'count': 2, 'items': []});
      await api.opportunities(limit: 20);
      expect(requested.single.path, '/market/opportunities');
      expect(requested.single.queryParameters['limit'], '20');
    });

    test('opportunities unwrap the scanned/count/items envelope', () async {
      final api = clientReturning(const {
        'scanned': 143,
        'count': 1,
        'items': [
          {'symbol': 'BONK', 'score': 91},
        ],
      });
      final result = await api.opportunities();
      expect(result.scanned, 143);
      expect(result.count, 1);
      expect(result.items.single.symbol, 'BONK');
    });

    test('settings hit /bot/settings', () async {
      final api = clientReturning(const {'max_open_positions': 5, 'alerts_enabled': true});
      final settings = await api.riskSettings();
      expect(requested.single.path, '/bot/settings');
      expect(settings.maxOpenPositions, 5);
      expect(settings.alertsEnabled, isTrue);
    });

    test('start, stop and close-all are three distinct endpoints', () async {
      final api = clientReturning(const {'ok': true});
      await api.startBot();
      await api.stopBot();
      await api.closeAll();
      expect(
        requested.map((u) => u.path).toList(),
        ['/bot/start', '/bot/stop', '/bot/close-all'],
      );
    });

    test('close-all posts a reason', () async {
      final api = clientReturning(const {'ok': true});
      await api.closeAll(reason: 'user tapped close all');
      expect(jsonDecode(sent.single.body)['reason'], 'user tapped close all');
    });

    test('trades and logs honour the limit', () async {
      final api = clientReturning(const <Map<String, dynamic>>[]);
      await api.trades(limit: 10);
      await api.logs(limit: 20);
      expect(requested[0].queryParameters['limit'], '10');
      expect(requested[1].path, '/logs');
      expect(requested[1].queryParameters['limit'], '20');
    });
  });

  group('contract: positions', () {
    test('open positions use status=open', () async {
      final api = clientReturning(const <Map<String, dynamic>>[]);
      await api.positions(open: true);
      expect(requested.single.queryParameters['status'], 'open');
    });

    test('closed positions use status=closed', () async {
      final api = clientReturning(const <Map<String, dynamic>>[]);
      await api.positions(open: false);
      expect(requested.single.queryParameters['status'], 'closed');
    });

    test('allPositions merges both calls, open first', () async {
      var call = 0;
      final mock = MockClient((request) async {
        requested.add(request.url);
        call++;
        final body = call == 1
            ? [
                {'id': 'o1', 'symbol': 'BONK', 'status': 'open'},
              ]
            : [
                {'id': 'c1', 'symbol': 'WIF', 'status': 'closed'},
              ];
        return http.Response(jsonEncode(body), 200);
      });
      final api = ApiClient(client: mock, baseUrl: 'http://test.local');

      final positions = await api.allPositions();
      expect(positions, hasLength(2));
      expect(positions.first.isOpen, isTrue);
      expect(positions.last.isOpen, isFalse);
      expect(requested, hasLength(2));
    });
  });

  group('contract: auth', () {
    test('nonce is a GET carrying the wallet address', () async {
      final api = clientReturning(const {'nonce': 'n-1', 'message': 'sign me'});
      final challenge = await api.requestNonce('0xabc');
      expect(requested.single.path, '/auth/nonce');
      expect(requested.single.queryParameters['wallet_address'], '0xabc');
      expect(challenge.nonce, 'n-1');
      expect(challenge.message, 'sign me');
    });

    test('login posts the signed message and stores the JWT', () async {
      final api = clientReturning(const {'access_token': 'jwt-123'});
      final token = await api.exchangeToken(
        walletAddress: '0xabc',
        message: 'sign me',
        signature: 'sig',
      );
      expect(token, 'jwt-123');
      expect(api.token, 'jwt-123');

      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['wallet_address'], '0xabc');
      expect(body['message'], 'sign me');
      expect(body['signature'], 'sig');
    });

    test('the JWT becomes a bearer header on later calls', () async {
      final api = clientReturning(const {'access_token': 'jwt-123'});
      await api.exchangeToken(
        walletAddress: '0xabc',
        message: 'm',
        signature: 's',
      );
      await api.portfolio();
      expect(sent.last.headers['Authorization'], 'Bearer jwt-123');
    });
  });

  group('contract: live execution', () {
    test('pending transactions are read from the mode/items envelope', () async {
      final api = clientReturning(const {
        'mode': 'jupiter',
        'items': [
          {'symbol': 'BONK', 'side': 'buy'},
        ],
      });
      final pending = await api.pendingTxs();
      expect(requested.single.path, '/bot/pending-tx');
      expect(pending.single['symbol'], 'BONK');
    });

    test('a signed transaction is submitted with its context', () async {
      final api = clientReturning(const {'ok': true});
      await api.submitSignedTransaction(
        signedTransaction: 'base64tx',
        symbol: 'BONK',
        side: 'buy',
        positionId: 'p1',
      );
      expect(requested.single.path, '/wallet/tx/submit');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['signed_transaction'], 'base64tx');
      expect(body['symbol'], 'BONK');
      expect(body['position_id'], 'p1');
    });
  });

  group('error handling', () {
    test('an empty list payload is handled', () async {
      final api = clientReturning(const <Map<String, dynamic>>[]);
      expect(await api.trades(), isEmpty);
    });

    test('a 401 becomes an ApiException flagged unauthorized', () async {
      final api = clientReturning({'detail': 'Not authenticated'}, status: 401);
      await expectLater(
        api.portfolio(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((e) => e.message, 'message', 'Not authenticated'),
        ),
      );
    });

    test('a 409 surfaces the backend detail message', () async {
      final api = clientReturning({'detail': 'Bot already running'}, status: 409);
      await expectLater(
        api.startBot(),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', 'Bot already running'),
        ),
      );
    });

    test('an unreachable host produces a friendly error', () async {
      final mock = MockClient((_) async => throw const TransportFailure());
      final api = ApiClient(client: mock, baseUrl: 'http://test.local');
      await expectLater(
        api.health(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Cannot reach backend'),
          ),
        ),
      );
    });
  });
}

/// Stands in for a socket failure without importing dart:io into tests.
class TransportFailure implements Exception {
  const TransportFailure();
  @override
  String toString() => 'connection refused';
}
