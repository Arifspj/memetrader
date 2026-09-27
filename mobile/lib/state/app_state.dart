import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/ws_client.dart';
import '../models/models.dart';
import '../wallet/local_signer.dart';
import 'token_store.dart';
enum AuthStatus { signedOut, connecting, signedIn }

/// Single source of truth for the UI.
///
/// This class only *stores* and *forwards* backend data. Every decision
/// (buy, sell, TP, SL, score) is made by the Python engine.
class AppState extends ChangeNotifier {
  /// One ApiClient is shared with the WebSocket client on purpose: the socket
  /// reads the JWT from it, so a second instance would silently send an
  /// unauthenticated `/ws/stream?token=` and get a 403 handshake.
  factory AppState({ApiClient? api, WsClient? ws, TokenStore? store}) {
    final client = api ?? ApiClient();
    return AppState._(client, ws ?? WsClient(api: client), store ?? const SecureTokenStore());
  }

  AppState._(this.api, this._ws, this._storage) {
    _ws.events.listen(_onWsEvent);
  }

  final ApiClient api;
  final WsClient _ws;
  final TokenStore _storage;

  // --- auth ----------------------------------------------------------------

  AuthStatus _auth = AuthStatus.signedOut;
  String? _walletAddress;
  String? _authError;
  bool _busy = false;

  AuthStatus get auth => _auth;
  String? get walletAddress => _walletAddress;
  String? get authError => _authError;
  bool get isSignedIn => _auth == AuthStatus.signedIn;

  // --- data ----------------------------------------------------------------

  Portfolio _portfolio = Portfolio.empty;

  /// False until a real portfolio payload has been parsed. Screens use this to
  /// print a placeholder instead of a `$0.00` that would read like a wiped
  /// account when the truth is simply "the number could not be loaded".
  bool _hasPortfolio = false;
  BotStatus? _botStatus;
  OpportunityList _opportunityList = OpportunityList.empty;
  List<Position> _positions = const [];
  List<Trade> _trades = const [];
  List<LogEntry> _logs = const [];
  RiskSettings _risk = RiskSettings.empty;
  WalletInfo? _wallet;
  Map<String, dynamic> _health = const {};
  String? _connectionError;

  /// Last open-position count seen on the stream, used to decide when the
  /// position/trade lists need refetching.
  int? _lastStreamedOpenCount;

  Portfolio get portfolio => _portfolio;

  /// Whether [portfolio] holds a value that actually came from the backend.
  bool get hasPortfolio => _hasPortfolio;
  BotStatus? get botStatus => _botStatus;
  List<Opportunity> get opportunities => _opportunityList.items;
  int get tokensScanned => _opportunityList.scanned;
  List<Position> get positions => _positions;
  List<Trade> get trades => _trades;
  List<LogEntry> get logs => _logs;
  RiskSettings get risk => _risk;
  WalletInfo? get wallet => _wallet;
  Map<String, dynamic> get health => _health;
  String? get connectionError => _connectionError;

  WsStatus get wsStatus => _ws.status;
  ValueListenable<WsStatus> get wsConnection => _ws.connection;

  bool get isLive => _botStatus?.state.isLive ?? false;
  bool get isScanning => _botStatus?.scanning ?? false;
  String get executionMode => _botStatus?.mode ?? _wallet?.executionMode ?? 'paper';
  bool get isPaperMode => executionMode == 'paper';

  List<Position> get openPositions =>
      _positions.where((p) => p.isOpen).toList(growable: false);
  List<Position> get closedPositions =>
      _positions.where((p) => !p.isOpen).toList(growable: false);

  // --- auth flow -----------------------------------------------------------

  Future<bool> restoreSession() async {
    try {
      final token = await _storage.read('jwt');
      final address = await _storage.read('wallet_address');
      if (token == null || address == null) return false;
      api.token = token;
      _walletAddress = address;
      _auth = AuthStatus.signedIn;
      _ws.connect();
      await refreshAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Full Phantom Connect flow: nonce -> sign the server message -> JWT.
  Future<bool> signIn({
    required String walletAddress,
    required Future<String> Function(String message) signMessage,
  }) async {
    _auth = AuthStatus.connecting;
    _authError = null;
    notifyListeners();
    try {
      final challenge = await api.requestNonce(walletAddress);
      final signature = await signMessage(challenge.message);
      final token = await api.exchangeToken(
        walletAddress: walletAddress,
        message: challenge.message,
        signature: signature,
      );
      await _storage.write('jwt', token);
      await _storage.write('wallet_address', walletAddress);
      _walletAddress = walletAddress;
      _auth = AuthStatus.signedIn;
      _ws.connect();
      await refreshAll();
      return true;
    } on ApiException catch (e) {
      _authError = e.message;
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return false;
    } catch (e) {
      _authError = e.toString();
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return false;
    }
  }

  /// MVP verification path: a self-custodial devnet wallet held on-device.
  /// The seed is never persisted and never leaves the app; only the derived
  /// address and the nonce signature reach the backend.
  Future<bool> signInWithSeedPhrase(String seedPhrase) async {
    final signer = await LocalSigner.fromSeedPhrase(seedPhrase);
    return signIn(walletAddress: signer.address, signMessage: signer.sign);
  }

  /// Debug-only convenience: signs in with a freshly generated throwaway
  /// devnet key so the UI can be exercised without a real wallet.
  Future<bool> signInWithDevWallet() async {
    final signer = await LocalSigner.fromSeed(generateDevnetSeed());
    return signIn(walletAddress: signer.address, signMessage: signer.sign);
  }

  Future<void> signOut() async {
    await _storage.delete('jwt');
    await _storage.delete('wallet_address');
    api.token = null;
    _walletAddress = null;
    _auth = AuthStatus.signedOut;
    _botStatus = null;
    notifyListeners();
  }

  // --- data loading --------------------------------------------------------

  Future<void> refreshAll() async {
    if (!isSignedIn) return;
    // Every loader runs concurrently, so a loader must not touch
    // `_connectionError` itself: a fast successful call would otherwise wipe
    // the error a slower failing call had just recorded. The cycle decides the
    // message once all of them have reported.
    final errors = await Future.wait([
      _load(() => api.portfolio(), (v) {
        _portfolio = v;
        _hasPortfolio = true;
      }),
      _load(() => api.botState(), (v) => _botStatus = v),
      _load(() => api.opportunities(limit: 20), (v) => _opportunityList = v),
      _load(() => api.allPositions(), (v) => _positions = v),
      _load(() => api.trades(limit: 50), (v) => _trades = v),
      _load(() => api.logs(limit: 50), (v) => _logs = v),
      _load(() => api.riskSettings(), (v) => _risk = v),
      _load(() => api.wallet(), (v) => _wallet = v),
    ]);
    _connectionError = _pickError(errors);
    notifyListeners();
  }

  /// The single message to show for one refresh cycle. An expired session
  /// outranks everything; otherwise the first real failure is reported.
  String? _pickError(List<String?> errors) {
    if (errors.isEmpty) return null;
    for (final e in errors) {
      if (e != null && e.startsWith('Session expired')) return e;
    }
    for (final e in errors) {
      if (e != null) return e;
    }
    return null;
  }

  /// Trade list refetches are fire-and-forget and can overlap. This counter
  /// identifies the newest one so a slow older response cannot overwrite it.
  int _refreshTicket = 0;

  /// The stream reports how many positions are open, not which ones, and no
  /// trade list at all. When that count moves, the lists are refetched - so the
  /// History and position rows stay truthful without polling on every frame.
  void _refreshListsIfCountsChanged() {
    final streamed = _botStatus?.openPositions;
    if (streamed == null) return;
    if (streamed == _lastStreamedOpenCount) return;
    final first = _lastStreamedOpenCount == null;
    _lastStreamedOpenCount = streamed;
    if (first) return; // initial frame matches the REST snapshot just fetched
    unawaited(_refreshTradeLists());
  }

  Future<void> _refreshTradeLists() async {
    // The count can move again while a refetch is in flight, so several
    // refetches run at once. They can complete out of order, and letting an
    // older response land last would leave the screen showing a position count
    // the backend no longer has. Only the newest refetch may apply its result.
    final ticket = ++_refreshTicket;
    try {
      final results = await Future.wait([
        api.allPositions(),
        api.trades(limit: 100),
      ]);
      final portfolio = await api.portfolio();
      if (ticket != _refreshTicket) return; // a newer refetch superseded this one
      _positions = results[0] as List<Position>;
      _trades = results[1] as List<Trade>;
      _portfolio = portfolio;
      _hasPortfolio = true;
      notifyListeners();
    } on ApiException {
      // The stream keeps the counters correct; a failed list refresh is not
      // worth surfacing on top of that.
    } catch (_) {
      // Same rationale as above.
    }
  }

  Future<void> refreshHealth() async {
    try {
      _health = await api.health();
      _connectionError = null;
    } on ApiException catch (e) {
      _connectionError = e.message;
      _health = const {};
    }
    notifyListeners();
  }

  /// Fetches one snapshot and applies it, returning the failure message for
  /// the calling cycle instead of mutating shared state itself.
  Future<String?> _load<T>(
    Future<T> Function() fetch,
    void Function(T) apply,
  ) async {
    try {
      apply(await fetch());
      return null;
    } on ApiException catch (e) {
      if (e.isUnauthorized) return 'Session expired. Sign in again.';
      return e.message;
    } on PayloadFormatException catch (e) {
      return e.userMessage;
    } catch (e) {
      return 'Unable to update trading data. Please retry. ($e)';
    }
  }

  // --- bot commands --------------------------------------------------------

  Future<void> _command(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (e) {
      _connectionError = e.message;
    } finally {
      _busy = false;
      await refreshAll();
      notifyListeners();
    }
  }

  bool get isBusy => _busy;

  Future<void> startBot() => _command(api.startBot);
  Future<void> stopBot() => _command(api.stopBot);
  Future<void> closeAll() => _command(api.closeAll);

  // --- realtime ------------------------------------------------------------

  void _onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'state':
      case 'bot_state':
        // The stream frame carries the bot status, a partial portfolio and the
        // newest engine log lines. Positions and trades are *lists*, and the
        // stream only sends a count, so a changed count triggers a REST refresh
        // of those lists.
        _botStatus = (_botStatus ?? BotStatus.fromJson(event)).mergedWithStream(event);
        _portfolio = _portfolio.mergedWithStream(event);
        _opportunityList = _opportunityList.mergedWithStream(event);
        _mergeLatestLogs(event['latest']);
        _refreshListsIfCountsChanged();
      case 'pnl_update':
        _portfolio = Portfolio.fromJson(event);
      case 'position_update':
        _applyPosition(event);
      case 'trade':
        _trades = [Trade.fromJson(event), ..._trades];
      case 'opportunity':
        _applyOpportunity(event);
      case 'ai_log':
        _prependLog(_logFromEvent(event));
      case 'risk_alert':
        _prependLog(
          LogEntry(
            id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
            level: 'warning',
            category: 'risk',
            symbol: event['symbol'] as String?,
            message: event['message'] as String? ?? 'Risk alert',
            payload: event,
            createdAt: DateTime.now(),
          ),
        );
      case 'error':
        _connectionError = event['message'] as String? ?? 'Backend error';
      default:
        return; // unknown event types are ignored on purpose
    }
    notifyListeners();
  }

  /// The stream repeats the same five newest events every tick, so only unseen
  /// ids are prepended - otherwise the log would flicker on every frame.
  void _mergeLatestLogs(dynamic latest) {
    if (latest is! List) return;
    for (final raw in latest.reversed) {
      if (raw is! Map) continue;
      final entry = LogEntry.fromJson(raw.cast<String, dynamic>());
      if (_logs.any((existing) => existing.id == entry.id)) continue;
      _logs = [entry, ..._logs];
    }
    if (_logs.length > 100) _logs = _logs.take(100).toList(growable: false);
  }

  void _applyPosition(Map<String, dynamic> event) {
    final incoming = Position.fromJson(event);
    final next = [..._positions];
    final index = next.indexWhere((p) => p.id == incoming.id);
    if (index >= 0) {
      next[index] = incoming;
    } else {
      next.insert(0, incoming);
    }
    _positions = next;
    // A close changes realised P&L, so refresh the authoritative numbers.
    if (!incoming.isOpen) unawaited(refreshAll());
  }

  void _applyOpportunity(Map<String, dynamic> event) {
    final incoming = Opportunity.fromJson(event);
    final next = [..._opportunityList.items];
    final index = next.indexWhere((o) => o.pairAddress == incoming.pairAddress);
    if (index >= 0) {
      next[index] = incoming;
    } else {
      next.insert(0, incoming);
    }
    _opportunityList = OpportunityList(
      scanned: _opportunityList.scanned,
      items: next.take(30).toList(growable: false),
    );
  }

  LogEntry _logFromEvent(Map<String, dynamic> event) {
    // The spec example: {symbol, action, score, reason, timestamp}.
    final symbol = event['symbol'] as String?;
    final action = event['action'] as String? ?? 'update';
    final score = event['score'];
    final reason = event['reason'] as String?;
    final parts = <String>[
      if (symbol != null) symbol,
      action,
      if (score is num) 'Score ${score.toInt()}',
      if (reason != null) reason,
    ];
    return LogEntry(
      id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
      level: event['level'] as String? ?? 'info',
      category: event['category'] as String? ?? 'ai',
      symbol: symbol,
      message: parts.join(' - '),
      payload: event,
      createdAt: DateTime.tryParse(event['timestamp']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  void _prependLog(LogEntry entry) {
    _logs = [entry, ..._logs].take(100).toList(growable: false);
  }

  /// One-shot log fetch used by pull-to-refresh.
  Future<void> refreshLogs() async {
    _connectionError = await _load(() => api.logs(limit: 50), (v) => _logs = v);
    notifyListeners();
  }

  /// Exposed for wiring tests that assert the socket shares this token.
  @visibleForTesting
  WsClient get socket => _ws;

  /// Exposed so tests can drive overlapping list refetches deterministically.
  @visibleForTesting
  void debugRefreshTradeLists() => unawaited(_refreshTradeLists());

  @override
  void dispose() {
    _ws.dispose();
    api.dispose();
    super.dispose();
  }
}
