import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin REST client. No trading logic lives here - it only calls the backend and
/// parses what the backend already decided.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Bearer token set after `/auth/verify`. Also forwarded to the WebSocket.
  String? token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse(
    '$_baseUrl$path',
  ).replace(
    queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
  );

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final uri = _uri(path, query);
    late http.Response res;
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(AppConfig.requestTimeout);
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('Backend timed out. Is the API running?');
    } catch (e) {
      throw ApiException('Cannot reach backend at $_baseUrl ($e)');
    }

    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    String message = 'HTTP ${res.statusCode}';
    if (decoded is Map && decoded['detail'] != null) {
      final detail = decoded['detail'];
      message = detail is String ? detail : jsonEncode(detail);
    }
    throw ApiException(message, statusCode: res.statusCode);
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) =>
      _send('GET', path, query: query);
  Future<dynamic> _post(String path, [Object? body]) => _send('POST', path, body: body);

  List<dynamic> _list(dynamic decoded) => decoded is List ? decoded : const [];

  // --- health / auth -------------------------------------------------------

  Future<Map<String, dynamic>> health() async =>
      (await _get('/health')) as Map<String, dynamic>;

  /// Step 1: `GET /auth/nonce?wallet_address=...` returns the nonce and the
  /// exact human-readable message that must be signed.
  Future<AuthChallenge> requestNonce(String walletAddress) async {
    final json =
        await _get('/auth/nonce', {'wallet_address': walletAddress})
            as Map<String, dynamic>;
    return AuthChallenge(
      nonce: json['nonce'] as String,
      message: json['message'] as String,
    );
  }

  /// Step 3: `POST /auth/login` with the signed message, returns a JWT.
  /// The private key is never seen, transmitted or stored by this app.
  Future<String> exchangeToken({
    required String walletAddress,
    required String message,
    required String signature,
  }) async {
    final json = await _post('/auth/login', {
      'wallet_address': walletAddress,
      'message': message,
      'signature': signature,
    }) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String;
    token = accessToken;
    return accessToken;
  }

  // --- portfolio / bot -----------------------------------------------------

  Future<Portfolio> portfolio() async =>
      Portfolio.fromJson((await _get('/portfolio')) as Map<String, dynamic>);

  Future<BotStatus> botState() async =>
      BotStatus.fromJson((await _get('/bot/state')) as Map<String, dynamic>);

  Future<void> startBot() => _post('/bot/start');

  /// Stops NEW buys. Open positions keep being managed by the backend.
  Future<void> stopBot() => _post('/bot/stop');

  /// Force-exits every open position. Separate from stop on purpose.
  Future<void> closeAll({String reason = 'manual close all'}) =>
      _post('/bot/close-all', {'reason': reason});

  Future<OpportunityList> opportunities({int limit = 20}) async =>
      OpportunityList.fromJson(
        (await _get('/market/opportunities', {'limit': limit}))
            as Map<String, dynamic>,
      );

  /// `status=open` returns open positions, anything else returns closed ones.
  Future<List<Position>> positions({required bool open}) async => _list(
    await _get('/positions', {'status': open ? 'open' : 'closed'}),
  ).map((e) => Position.fromJson(e as Map<String, dynamic>)).toList();

  /// The backend has no "all" filter, so the two calls are merged here.
  Future<List<Position>> allPositions() async {
    final results = await Future.wait([
      positions(open: true),
      positions(open: false),
    ]);
    return [...results[0], ...results[1]];
  }

  Future<List<Trade>> trades({int limit = 100}) async => _list(
    await _get('/trades', {'limit': limit}),
  ).map((e) => Trade.fromJson(e as Map<String, dynamic>)).toList();

  Future<List<LogEntry>> logs({int limit = 100}) async => _list(
    await _get('/logs', {'limit': limit}),
  ).map((e) => LogEntry.fromJson(e as Map<String, dynamic>)).toList();

  Future<RiskSettings> riskSettings() async =>
      RiskSettings.fromJson((await _get('/bot/settings')) as Map<String, dynamic>);

  Future<WalletInfo> wallet() async =>
      WalletInfo.fromJson((await _get('/wallet')) as Map<String, dynamic>);

  /// Unsigned Jupiter transactions waiting for the wallet to sign.
  /// Returns the `items` list from `{mode, items}`.
  Future<List<Map<String, dynamic>>> pendingTxs() async {
    final json = await _get('/bot/pending-tx') as Map<String, dynamic>;
    return _list(json['items']).cast<Map<String, dynamic>>();
  }

  Future<void> submitSignedTransaction({
    required String signedTransaction,
    String? symbol,
    String? side,
    String? positionId,
  }) => _post('/wallet/tx/submit', {
    'signed_transaction': signedTransaction,
    if (symbol != null) 'symbol': symbol,
    if (side != null) 'side': side,
    if (positionId != null) 'position_id': positionId,
  });

  void dispose() => _client.close();
}

/// Nonce plus the exact message text the backend expects to be signed.
class AuthChallenge {
  const AuthChallenge({required this.nonce, required this.message});

  final String nonce;
  final String message;
}
