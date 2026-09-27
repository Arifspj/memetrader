/// Data models mirroring the backend JSON exactly.
///
/// The backend is the single source of truth: Flutter never computes a score,
/// a P&L, a TP or a stop. It only parses and renders.
library;

/// Thrown when a field that has to be a number arrives as something unusable.
///
/// Silently coercing corrupt data to `0` would let a broken backend response
/// render as a plausible-looking balance, so a malformed value is surfaced
/// instead of swallowed.
class PayloadFormatException implements Exception {
  const PayloadFormatException(this.field, this.value);

  final String field;
  final Object? value;

  /// Copy suitable for showing to a user.
  String get userMessage =>
      'Unable to update trading data. The backend sent an unexpected value for '
      '"$field". Please retry.';

  @override
  String toString() => 'PayloadFormatException: $field was ${value.runtimeType} ($value)';
}

double _d(dynamic value, [String field = 'number']) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw PayloadFormatException(field, value);
}

int _i(dynamic value, [String field = 'number']) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw PayloadFormatException(field, value);
}

DateTime? _dt(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

class Portfolio {
  const Portfolio({
    required this.equityUsd,
    required this.cashUsd,
    required this.investedUsd,
    required this.realizedPnlUsd,
    required this.unrealizedPnlUsd,
    required this.todayPnlUsd,
    required this.todayPnlPct,
    required this.openPositions,
    required this.totalTrades,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.startingCapitalUsd,
  });

  final double equityUsd;
  final double cashUsd;
  final double investedUsd;
  final double realizedPnlUsd;
  final double unrealizedPnlUsd;
  final double todayPnlUsd;
  final double todayPnlPct;
  final int openPositions;
  final int totalTrades;
  final int wins;
  final int losses;
  final double? winRate;
  final double startingCapitalUsd;

  /// Balance shown as "AVAILABLE BALANCE" - cash not tied up in a position.
  double get availableUsd => cashUsd;

  /// Total P&L since inception, in percent of starting capital.
  double get allTimePnlUsd => equityUsd - startingCapitalUsd;
  double get allTimePnlPct => startingCapitalUsd > 0
      ? (allTimePnlUsd / startingCapitalUsd) * 100
      : 0;

  static const empty = Portfolio(
    equityUsd: 0,
    cashUsd: 0,
    investedUsd: 0,
    realizedPnlUsd: 0,
    unrealizedPnlUsd: 0,
    todayPnlUsd: 0,
    todayPnlPct: 0,
    openPositions: 0,
    totalTrades: 0,
    wins: 0,
    losses: 0,
    winRate: null,
    startingCapitalUsd: 0,
  );

  factory Portfolio.fromJson(Map<String, dynamic> json) => Portfolio(
    equityUsd: _d(json['equity_usd'], 'equity_usd'),
    cashUsd: _d(json['cash_usd'], 'cash_usd'),
    investedUsd: _d(json['invested_usd'], 'invested_usd'),
    realizedPnlUsd: _d(json['realized_pnl_usd'], 'realized_pnl_usd'),
    unrealizedPnlUsd: _d(json['unrealized_pnl_usd'], 'unrealized_pnl_usd'),
    todayPnlUsd: _d(json['today_pnl_usd'], 'today_pnl_usd'),
    todayPnlPct: _d(json['today_pnl_pct'], 'today_pnl_pct'),
    openPositions: _i(json['open_positions'], 'open_positions'),
    totalTrades: _i(json['total_trades'], 'total_trades'),
    wins: _i(json['wins'], 'wins'),
    losses: _i(json['losses'], 'losses'),
    winRate: json['win_rate'] == null ? null : _d(json['win_rate'], 'win_rate'),
    startingCapitalUsd: _d(json['starting_capital_usd'], 'starting_capital_usd'),
  );

  /// Applies the *partial* snapshot that `/ws/stream` repeats every tick.
  ///
  /// The stream deliberately carries only equity, today's P&L, the open
  /// position count and the win rate. Re-parsing the whole object with
  /// [fromJson] would zero cash, cost basis and the trade tallies on every
  /// frame, so only the fields the stream actually owns are replaced and the
  /// rest are carried over from the last full REST snapshot.
  Portfolio mergedWithStream(Map<String, dynamic> json) {
    if (json.isEmpty) return this;
    final equity = json.containsKey('equity_usd') ? _d(json['equity_usd'], 'equity_usd') : equityUsd;
    final todayPnl =
        json.containsKey('today_pnl_usd') ? _d(json['today_pnl_usd'], 'today_pnl_usd') : todayPnlUsd;
    final cash = json.containsKey('cash_usd') ? _d(json['cash_usd'], 'cash_usd') : cashUsd;
    // Keep the identity equity == cash + invested so the two balance views can
    // never disagree on screen.
    final invested = json.containsKey('invested_usd')
        ? _d(json['invested_usd'], 'invested_usd')
        : (equity - cash < 0 ? 0.0 : equity - cash);
    return Portfolio(
      equityUsd: equity,
      cashUsd: cash,
      investedUsd: invested,
      realizedPnlUsd: json.containsKey('realized_pnl_usd')
          ? _d(json['realized_pnl_usd'], 'realized_pnl_usd')
          : realizedPnlUsd,
      unrealizedPnlUsd: json.containsKey('unrealized_pnl_usd')
          ? _d(json['unrealized_pnl_usd'], 'unrealized_pnl_usd')
          : unrealizedPnlUsd,
      todayPnlUsd: todayPnl,
      todayPnlPct: json.containsKey('today_pnl_pct')
          ? _d(json['today_pnl_pct'], 'today_pnl_pct')
          : (startingCapitalUsd > 0 ? (todayPnl / startingCapitalUsd) * 100 : 0),
      openPositions: json.containsKey('open_positions')
          ? _i(json['open_positions'], 'open_positions')
          : openPositions,
      totalTrades: json.containsKey('total_trades') ? _i(json['total_trades'], 'total_trades') : totalTrades,
      wins: json.containsKey('wins') ? _i(json['wins'], 'wins') : wins,
      losses: json.containsKey('losses') ? _i(json['losses'], 'losses') : losses,
      winRate: json.containsKey('win_rate') && json['win_rate'] != null
          ? _d(json['win_rate'], 'win_rate')
          : (json.containsKey('win_rate') ? null : winRate),
      startingCapitalUsd: json.containsKey('starting_capital_usd')
          ? _d(json['starting_capital_usd'], 'starting_capital_usd')
          : startingCapitalUsd,
    );
  }
}

enum BotState {
  running,
  stopped,
  unknown;

  static BotState parse(String? raw) => switch (raw) {
    'running' => BotState.running,
    'stopped' => BotState.stopped,
    _ => BotState.unknown,
  };

  bool get isLive => this == BotState.running;
}

class BotStatus {
  const BotStatus({
    required this.state,
    required this.mode,
    required this.scanning,
    required this.tokensScanned,
    required this.opportunities,
    required this.openPositions,
    required this.equityUsd,
    required this.todayPnlUsd,
    required this.todayTrades,
    required this.winRate,
    this.runId,
    this.startedAt,
    this.lastHeartbeat,
    this.pendingTxs = 0,
  });

  final BotState state;
  final String mode;
  final bool scanning;
  final int tokensScanned;
  final int opportunities;
  final int openPositions;
  final double equityUsd;
  final double todayPnlUsd;
  final int todayTrades;
  final double? winRate;
  final String? runId;
  final DateTime? startedAt;
  final DateTime? lastHeartbeat;

  /// Only sent on the WebSocket `state` frame (live Jupiter approvals).
  final int pendingTxs;

  static BotStatus fromJson(Map<String, dynamic> json) => BotStatus(
    state: BotState.parse(json['state'] as String?),
    mode: json['mode'] as String? ?? 'paper',
    scanning: json['scanning'] == true,
    tokensScanned: _i(json['tokens_scanned'], 'tokens_scanned'),
    opportunities: _i(json['opportunities'], 'opportunities'),
    openPositions: _i(json['open_positions'], 'open_positions'),
    equityUsd: _d(json['equity_usd'], 'equity_usd'),
    todayPnlUsd: _d(json['today_pnl_usd'], 'today_pnl_usd'),
    todayTrades: _i(json['today_trades']),
    winRate: json['win_rate'] == null ? null : _d(json['win_rate'], 'win_rate'),
    runId: json['run_id'] as String?,
    startedAt: _dt(json['started_at']),
    lastHeartbeat: _dt(json['last_heartbeat']),
    pendingTxs: _i(json['pending_txs'], 'pending_txs'),
  );

  /// Folds a `/ws/stream` frame into the last full REST status.
  ///
  /// The stream is missing fields that `/bot/state` does send - `today_trades`
  /// and `run_id` among them - so re-parsing it with [fromJson] would show
  /// "0 trades today" three seconds after the REST call reported the real
  /// number. Fields absent from the frame keep their REST value.
  BotStatus mergedWithStream(Map<String, dynamic> json) {
    if (json.isEmpty) return this;
    return BotStatus(
      state: json.containsKey('state') ? BotState.parse(json['state'] as String?) : state,
      mode: (json['mode'] as String?) ?? mode,
      scanning: json.containsKey('scanning') ? json['scanning'] == true : scanning,
      tokensScanned: json.containsKey('tokens_scanned') ? _i(json['tokens_scanned'], 'tokens_scanned') : tokensScanned,
      opportunities: json.containsKey('opportunities') ? _i(json['opportunities'], 'opportunities') : opportunities,
      openPositions: json.containsKey('open_positions') ? _i(json['open_positions'], 'open_positions') : openPositions,
      equityUsd: json.containsKey('equity_usd') ? _d(json['equity_usd'], 'equity_usd') : equityUsd,
      todayPnlUsd: json.containsKey('today_pnl_usd') ? _d(json['today_pnl_usd'], 'today_pnl_usd') : todayPnlUsd,
      todayTrades: json.containsKey('today_trades') ? _i(json['today_trades']) : todayTrades,
      winRate: json.containsKey('win_rate')
          ? (json['win_rate'] == null ? null : _d(json['win_rate'], 'win_rate'))
          : winRate,
      runId: (json['run_id'] as String?) ?? runId,
      startedAt: json.containsKey('started_at') ? _dt(json['started_at']) : startedAt,
      lastHeartbeat: json.containsKey('last_heartbeat') ? _dt(json['last_heartbeat']) : lastHeartbeat,
      pendingTxs: json.containsKey('pending_txs') ? _i(json['pending_txs'], 'pending_txs') : pendingTxs,
    );
  }
}

/// `GET /market/opportunities` returns a wrapper, not a bare list.
class OpportunityList {
  const OpportunityList({
    required this.scanned,
    required this.items,
    this.streamOpportunities = 0,
  });

  final int scanned;
  final List<Opportunity> items;

  /// Counter pushed by `/ws/stream`, which reports how many candidates the
  /// engine found without shipping the rows themselves.
  final int streamOpportunities;

  int get count => items.length;

  static const empty = OpportunityList(scanned: 0, items: []);

  factory OpportunityList.fromJson(Map<String, dynamic> json) => OpportunityList(
    scanned: _i(json['scanned'], 'scanned'),
    streamOpportunities: json.containsKey('opportunities')
        ? _i(json['opportunities'], 'opportunities')
        : _i(json['count'], 'count'),
    items:
        (json['items'] as List?)
            ?.map((e) => Opportunity.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  /// Folds the `tokens_scanned` / `opportunities` counters that `/ws/stream`
  /// sends every tick, keeping the opportunity rows from the REST snapshot.
  OpportunityList mergedWithStream(Map<String, dynamic> json) {
    if (json.isEmpty) return this;
    return OpportunityList(
      scanned: json.containsKey('tokens_scanned')
          ? _i(json['tokens_scanned'], 'tokens_scanned')
          : (json.containsKey('scanned') ? _i(json['scanned'], 'scanned') : scanned),
      streamOpportunities: json.containsKey('opportunities')
          ? _i(json['opportunities'], 'opportunities')
          : streamOpportunities,
      items: items,
    );
  }
}

class Opportunity {
  const Opportunity({
    required this.symbol,
    required this.mint,
    required this.pairAddress,
    required this.dexId,
    required this.priceUsd,
    required this.liquidityUsd,
    required this.volume5m,
    required this.priceChange5m,
    required this.buySellRatio,
    required this.score,
    required this.blockedReasons,
    required this.breakdown,
  });

  final String symbol;
  final String? mint;
  final String pairAddress;
  final String dexId;
  final double priceUsd;
  final double liquidityUsd;
  final double volume5m;
  final double priceChange5m;
  final double buySellRatio;
  final double score;

  /// Non-empty means the safety engine blocked it; the UI shows it as rejected.
  final List<String> blockedReasons;
  final Map<String, double> breakdown;

  bool get isBlocked => blockedReasons.isNotEmpty;
  bool get isBuying => !isBlocked && score >= 80;

  double? part(String key) => breakdown[key];

  factory Opportunity.fromJson(Map<String, dynamic> json) => Opportunity(
    symbol: json['symbol'] as String? ?? '???',
    mint: json['mint'] as String?,
    pairAddress: json['pair_address'] as String? ?? '',
    dexId: json['dex_id'] as String? ?? '',
    priceUsd: _d(json['price_usd'], 'price_usd'),
    liquidityUsd: _d(json['liquidity_usd'], 'liquidity_usd'),
    volume5m: _d(json['volume_5m']),
    priceChange5m: _d(json['price_change_5m']),
    buySellRatio: _d(json['buy_sell_ratio']),
    score: _d(json['score']),
    blockedReasons:
        (json['blocked_reasons'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    breakdown: (json['score_breakdown'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), _d(v)),
        ) ??
        const {},
  );
}

class Position {
  const Position({
    required this.id,
    required this.symbol,
    required this.name,
    required this.mint,
    required this.status,
    required this.qty,
    required this.entryPrice,
    required this.currentPrice,
    required this.investedUsd,
    required this.entryScore,
    required this.stopLoss,
    required this.takeProfit,
    required this.trailingStop,
    required this.unrealizedPnlUsd,
    required this.unrealizedPnlPct,
    required this.openedAt,
    required this.closedAt,
    required this.exitPrice,
    required this.exitReason,
    required this.realizedPnlUsd,
  });

  final String id;
  final String symbol;

  /// Token name from DexScreener, e.g. "Bonk Inu".
  final String? name;
  final String mint;
  final String status;
  final double qty;
  final double entryPrice;
  final double? currentPrice;
  final double investedUsd;
  final double entryScore;
  final double? stopLoss;
  final double? takeProfit;
  final double? trailingStop;
  final double unrealizedPnlUsd;
  final double unrealizedPnlPct;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double? exitPrice;
  final String? exitReason;
  final double? realizedPnlUsd;

  bool get isOpen => status == 'open';
  String get side => 'LONG';

  factory Position.fromJson(Map<String, dynamic> json) => Position(
    id: json['id'] as String? ?? '',
    symbol: json['symbol'] as String? ?? '???',
    name: json['name'] as String?,
    mint: json['mint'] as String? ?? '',
    status: json['status'] as String? ?? 'open',
    qty: _d(json['qty'], 'qty'),
    entryPrice: _d(json['entry_price'], 'entry_price'),
    currentPrice: json['current_price'] == null ? null : _d(json['current_price']),
    investedUsd: _d(json['invested_usd'], 'invested_usd'),
    entryScore: _d(json['entry_score']),
    stopLoss: json['stop_loss'] == null ? null : _d(json['stop_loss']),
    takeProfit: json['take_profit'] == null ? null : _d(json['take_profit']),
    trailingStop: json['trailing_stop'] == null ? null : _d(json['trailing_stop']),
    unrealizedPnlUsd: _d(json['unrealized_pnl_usd'], 'unrealized_pnl_usd'),
    unrealizedPnlPct: _d(json['unrealized_pnl_pct']),
    openedAt: _dt(json['opened_at']),
    closedAt: _dt(json['closed_at']),
    exitPrice: json['exit_price'] == null ? null : _d(json['exit_price'], 'exit_price'),
    exitReason: json['exit_reason'] as String?,
    realizedPnlUsd: json['realized_pnl_usd'] == null ? null : _d(json['realized_pnl_usd'], 'realized_pnl_usd'),
  );
}

class Trade {
  const Trade({
    required this.id,
    required this.side,
    required this.mode,
    required this.symbol,
    required this.usdAmount,
    required this.qty,
    required this.price,
    required this.reason,
    required this.pnlUsd,
    required this.txSignature,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String side;
  final String mode;
  final String symbol;
  final double usdAmount;
  final double qty;
  final double price;
  final String? reason;
  final double? pnlUsd;
  final String? txSignature;
  final String status;
  final DateTime? createdAt;

  bool get isBuy => side == 'buy';

  factory Trade.fromJson(Map<String, dynamic> json) => Trade(
    id: json['id'] as String? ?? '',
    side: json['side'] as String? ?? 'buy',
    mode: json['mode'] as String? ?? 'paper',
    symbol: json['symbol'] as String? ?? '???',
    usdAmount: _d(json['usd_amount'], 'usd_amount'),
    qty: _d(json['qty'], 'qty'),
    price: _d(json['price'], 'price'),
    reason: json['reason'] as String?,
    pnlUsd: json['pnl_usd'] == null ? null : _d(json['pnl_usd'], 'pnl_usd'),
    txSignature: json['tx_signature'] as String?,
    status: json['status'] as String? ?? 'filled',
    createdAt: _dt(json['created_at']),
  );
}

class LogEntry {
  const LogEntry({
    required this.id,
    required this.level,
    required this.category,
    required this.symbol,
    required this.message,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String level;
  final String category;
  final String? symbol;
  final String message;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  bool get isWarning => level == 'warning' || level == 'error';

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    id: json['id'] as String? ?? '',
    level: json['level'] as String? ?? 'info',
    category: json['category'] as String? ?? 'system',
    symbol: json['symbol'] as String?,
    message: json['message'] as String? ?? '',
    payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    createdAt: _dt(json['created_at']),
  );
}

class RiskSettings {
  const RiskSettings({
    required this.startingCapitalUsd,
    required this.riskPerTradePct,
    required this.maxOpenPositions,
    required this.maxDailyLossPct,
    required this.takeProfitPct,
    required this.stopLossPct,
    required this.trailingActivationPct,
    required this.trailingDropPct,
    required this.maxHoldMinutes,
    required this.minEntryScore,
    required this.reentryCooldownMinutes,
    required this.minLiquidityUsd,
    required this.minVolume5mUsd,
    required this.maxPriceImpactBps,
    required this.scanIntervalSeconds,
    required this.alertsEnabled,
  });

  final double startingCapitalUsd;
  final double riskPerTradePct;
  final int maxOpenPositions;
  final double maxDailyLossPct;
  final double takeProfitPct;
  final double stopLossPct;
  final double trailingActivationPct;
  final double trailingDropPct;
  final int maxHoldMinutes;
  final double minEntryScore;
  final int reentryCooldownMinutes;
  final double minLiquidityUsd;
  final double minVolume5mUsd;
  final double maxPriceImpactBps;
  final int scanIntervalSeconds;
  final bool alertsEnabled;

  static const empty = RiskSettings(
    startingCapitalUsd: 0,
    riskPerTradePct: 0,
    maxOpenPositions: 0,
    maxDailyLossPct: 0,
    takeProfitPct: 0,
    stopLossPct: 0,
    trailingActivationPct: 0,
    trailingDropPct: 0,
    maxHoldMinutes: 0,
    minEntryScore: 0,
    reentryCooldownMinutes: 0,
    minLiquidityUsd: 0,
    minVolume5mUsd: 0,
    maxPriceImpactBps: 0,
    scanIntervalSeconds: 0,
    alertsEnabled: false,
  );

  factory RiskSettings.fromJson(Map<String, dynamic> json) => RiskSettings(
    startingCapitalUsd: _d(json['starting_capital_usd'], 'starting_capital_usd'),
    riskPerTradePct: _d(json['risk_per_trade_pct']),
    maxOpenPositions: _i(json['max_open_positions']),
    maxDailyLossPct: _d(json['max_daily_loss_pct']),
    takeProfitPct: _d(json['take_profit_pct']),
    stopLossPct: _d(json['stop_loss_pct']),
    trailingActivationPct: _d(json['trailing_activation_pct']),
    trailingDropPct: _d(json['trailing_drop_pct']),
    maxHoldMinutes: _i(json['max_hold_minutes']),
    minEntryScore: _d(json['min_entry_score']),
    reentryCooldownMinutes: _i(json['reentry_cooldown_minutes']),
    minLiquidityUsd: _d(json['min_liquidity_usd']),
    minVolume5mUsd: _d(json['min_volume_5m_usd']),
    maxPriceImpactBps: _d(json['max_price_impact_bps']),
    scanIntervalSeconds: _i(json['scan_interval_seconds']),
    alertsEnabled: json['alerts_enabled'] == true,
  );
}

class WalletInfo {
  const WalletInfo({
    required this.walletAddress,
    required this.balanceSol,
    required this.balanceUsdc,
    required this.executionMode,
    required this.hasSessionKey,
  });

  final String walletAddress;
  final double? balanceSol;
  final double? balanceUsdc;
  final String executionMode;

  /// True when a delegated session signer is registered for unattended swaps.
  final bool hasSessionKey;

  factory WalletInfo.fromJson(Map<String, dynamic> json) => WalletInfo(
    walletAddress: json['wallet_address'] as String? ?? '',
    balanceSol: json['balance_sol'] == null ? null : _d(json['balance_sol']),
    balanceUsdc: json['balance_usdc'] == null ? null : _d(json['balance_usdc']),
    executionMode: json['execution_mode'] as String? ?? 'paper',
    hasSessionKey: json['has_session_key'] == true,
  );
}
