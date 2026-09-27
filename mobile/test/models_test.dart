import 'package:flutter_test/flutter_test.dart';
import 'package:memetrader_app/core/theme.dart';
import 'package:memetrader_app/models/models.dart';

void main() {
  streamFoldingTests();
  botStatusStreamTests();
  invalidPayloadTests();
  group('Portfolio.fromJson', () {
    test('parses a backend portfolio payload', () {
      final portfolio = Portfolio.fromJson(const {
        'equity_usd': 550164.38,
        'cash_usd': 550161.79,
        'invested_usd': 12.0,
        'realized_pnl_usd': 80153.22,
        'unrealized_pnl_usd': 2.5,
        'today_pnl_usd': -12.0,
        'today_pnl_pct': -0.5,
        'open_positions': 1,
        'total_trades': 9,
        'wins': 5,
        'losses': 4,
        'win_rate': 0.55,
        'starting_capital_usd': 470011.16,
      });

      expect(portfolio.equityUsd, 550164.38);
      expect(portfolio.availableUsd, 550161.79);
      expect(portfolio.openPositions, 1);
      expect(portfolio.winRate, 0.55);
    });

    test('survives missing keys', () {
      final portfolio = Portfolio.fromJson(const {});
      expect(portfolio.equityUsd, 0);
      expect(portfolio.winRate, isNull);
    });

    test('derives all-time P&L from starting capital', () {
      final portfolio = Portfolio.fromJson(const {
        'equity_usd': 1100,
        'starting_capital_usd': 1000,
      });
      expect(portfolio.allTimePnlUsd, 100);
      expect(portfolio.allTimePnlPct, closeTo(10, 0.001));
    });

    test('all-time P&L percent is zero when capital is unset', () {
      final portfolio = Portfolio.fromJson(const {'equity_usd': 500});
      expect(portfolio.allTimePnlPct, 0);
    });
  });

  group('BotStatus.fromJson', () {
    test('maps running state', () {
      final bot = BotStatus.fromJson(const {
        'state': 'running',
        'mode': 'paper',
        'scanning': true,
        'tokens_scanned': 143,
        'opportunities': 8,
        'open_positions': 3,
        'today_pnl_usd': 184.20,
      });

      expect(bot.state, BotState.running);
      expect(bot.state.isLive, isTrue);
      expect(bot.tokensScanned, 143);
      expect(bot.opportunities, 8);
    });

    test('treats an unknown state as not live', () {
      final bot = BotStatus.fromJson(const {'state': 'starting'});
      expect(bot.state, BotState.unknown);
      expect(bot.state.isLive, isFalse);
    });

    test('handles a missing state field', () {
      expect(BotStatus.fromJson(const {}).state, BotState.unknown);
    });
  });

  group('Opportunity.fromJson', () {
    test('parses score breakdown and detects buy signal', () {
      final opportunity = Opportunity.fromJson(const {
        'symbol': 'BONK',
        'pair_address': 'pair1',
        'dex_id': 'raydium',
        'price_usd': 0.0000142,
        'liquidity_usd': 1200000,
        'volume_5m': 45000,
        'score': 91,
        'score_breakdown': {'momentum': 94.0, 'safety': 88.0},
        'blocked_reasons': <String>[],
      });

      expect(opportunity.isBlocked, isFalse);
      expect(opportunity.isBuying, isTrue);
      expect(opportunity.part('momentum'), 94.0);
    });

    test('blocked opportunities never signal a buy', () {
      final opportunity = Opportunity.fromJson(const {
        'symbol': 'SCAM',
        'score': 95,
        'blocked_reasons': ['honeypot', 'no liquidity'],
      });

      expect(opportunity.isBlocked, isTrue);
      expect(opportunity.isBuying, isFalse);
      expect(opportunity.blockedReasons, hasLength(2));
    });

    test('tolerates a missing breakdown', () {
      final opportunity = Opportunity.fromJson(const {'symbol': 'X'});
      expect(opportunity.breakdown, isEmpty);
      expect(opportunity.part('momentum'), isNull);
    });
  });

  group('Position.fromJson', () {
    test('open position uses unrealised P&L', () {
      final position = Position.fromJson(const {
        'id': 'p1',
        'symbol': 'BONK',
        'status': 'open',
        'entry_price': 0.000014,
        'current_price': 0.000016,
        'unrealized_pnl_usd': 8.42,
        'unrealized_pnl_pct': 14.3,
      });

      expect(position.isOpen, isTrue);
      expect(position.side, 'LONG');
      expect(position.realizedPnlUsd, isNull);
    });

    test('closed position carries exit reason and realised P&L', () {
      final position = Position.fromJson(const {
        'id': 'p2',
        'symbol': 'WIF',
        'status': 'closed',
        'exit_price': 0.0021,
        'exit_reason': 'take_profit',
        'realized_pnl_usd': -3.1,
        'closed_at': '2026-01-02T03:04:05Z',
      });

      expect(position.isOpen, isFalse);
      expect(position.exitReason, 'take_profit');
      expect(position.closedAt, isNotNull);
    });
  });

  group('Trade.fromJson', () {
    test('parses a buy', () {
      final trade = Trade.fromJson(const {
        'id': 't1',
        'side': 'buy',
        'mode': 'paper',
        'symbol': 'BONK',
        'usd_amount': 50,
        'qty': 3512400,
        'price': 0.00001423,
      });

      expect(trade.isBuy, isTrue);
      expect(trade.pnlUsd, isNull);
    });

    test('parses a sell with P&L', () {
      final trade = Trade.fromJson(const {
        'side': 'sell',
        'symbol': 'WIF',
        'pnl_usd': -2.2,
      });

      expect(trade.isBuy, isFalse);
      expect(trade.pnlUsd, -2.2);
    });
  });

  group('LogEntry.fromJson', () {
    test('flags warnings', () {
      final log = LogEntry.fromJson(const {
        'id': 'l1',
        'level': 'warning',
        'message': 'Daily loss limit hit',
      });
      expect(log.isWarning, isTrue);
    });

    test('info logs are not warnings', () {
      expect(LogEntry.fromJson(const {'level': 'info'}).isWarning, isFalse);
    });
  });

  group('formatters', () {
    test('formatUsd always shows two decimals', () {
      expect(formatUsd(550161.79), '\$550,161.79');
      expect(formatUsd(0), '\$0.00');
    });

    test('formatSignedUsd adds a sign', () {
      expect(formatSignedUsd(184.2), '+\$184.20');
      expect(formatSignedUsd(-4.5), '-\$4.50');
    });

    test('formatPct adds a sign and keeps magnitude', () {
      expect(formatPct(12.38), '+12.38%');
      expect(formatPct(-3.4), '-3.40%');
    });

    test('formatPrice keeps small meme-coin prices readable', () {
      expect(formatPrice(123.4567), '\$123.4567');
      expect(formatPrice(0.0000142), '\$0.0000142');
      expect(formatPrice(0.0021), '\$0.0021');
      expect(formatPrice(0), '\$0');
    });

    test('formatCompactUsd abbreviates large numbers', () {
      expect(formatCompactUsd(1200000), '\$1.20M');
      expect(formatCompactUsd(2500), '\$2.5K');
      expect(formatCompactUsd(12), '\$12.00');
    });

    test('shortenAddress keeps both ends', () {
      expect(shortenAddress('0x43bb1234567890abcdef9876543273e0'), '0x43...73e0');
      expect(shortenAddress('short'), 'short');
    });

    test('pnlColor is green up and red down', () {
      expect(pnlColor(1), AppTheme.live);
      expect(pnlColor(-1), AppTheme.offline);
      expect(pnlColor(0), AppTheme.textSecondary);
    });
  });
}

// --- WebSocket stream folding -------------------------------------------
// The stream frame is a *partial* snapshot. Re-parsing it with fromJson would
// zero the fields it does not carry, which is how the Home screen used to show
// a frozen \$1,000.00 while the engine was trading.
void streamFoldingTests() {
  final rest = Portfolio.fromJson({
    'equity_usd': 1000.0,
    'cash_usd': 900.0,
    'invested_usd': 100.0,
    'realized_pnl_usd': 5.0,
    'unrealized_pnl_usd': 7.0,
    'today_pnl_usd': 12.0,
    'today_pnl_pct': 1.2,
    'open_positions': 1,
    'total_trades': 13,
    'wins': 4,
    'losses': 9,
    'win_rate': 30.77,
    'starting_capital_usd': 1000.0,
  });

  test('stream frame updates equity without zeroing the REST fields', () {
    final merged = rest.mergedWithStream({'equity_usd': 987.61, 'open_positions': 2});
    expect(merged.equityUsd, 987.61);
    expect(merged.openPositions, 2);
    // Carried over, not reset.
    expect(merged.cashUsd, 900.0);
    expect(merged.realizedPnlUsd, 5.0);
    expect(merged.unrealizedPnlUsd, 7.0);
    expect(merged.totalTrades, 13);
    expect(merged.wins, 4);
    expect(merged.losses, 9);
    expect(merged.winRate, 30.77);
    expect(merged.startingCapitalUsd, 1000.0);
  });

  test('stream frame keeps equity == cash + invested', () {
    final merged = rest.mergedWithStream({'equity_usd': 950.0});
    // cash is not in the stream, so invested is derived to keep the identity.
    expect(merged.investedUsd, closeTo(50.0, 0.001));
    expect(merged.cashUsd + merged.investedUsd, closeTo(merged.equityUsd, 0.001));
  });

  test("today's P&L percent is recomputed when the stream omits it", () {
    final merged = rest.mergedWithStream({'today_pnl_usd': -12.39});
    expect(merged.todayPnlUsd, -12.39);
    expect(merged.todayPnlPct, closeTo(-1.239, 0.001));
  });

  test('an empty stream frame changes nothing', () {
    expect(rest.mergedWithStream({}).equityUsd, rest.equityUsd);
    expect(rest.mergedWithStream({}).totalTrades, rest.totalTrades);
  });

  test('a null win_rate in the stream clears it rather than keeping stale', () {
    final merged = rest.mergedWithStream({'win_rate': null});
    expect(merged.winRate, isNull);
  });

  test('opportunity counters fold while the rows are kept', () {
    const list = OpportunityList(scanned: 0, items: []);
    final merged = list.mergedWithStream({'tokens_scanned': 50, 'opportunities': 37});
    expect(merged.scanned, 50);
    expect(merged.streamOpportunities, 37);
    expect(merged.items, isEmpty);
  });
}
void botStatusStreamTests() {
  final rest = BotStatus.fromJson({
    'state': 'running',
    'mode': 'paper',
    'scanning': true,
    'tokens_scanned': 50,
    'opportunities': 38,
    'open_positions': 3,
    'equity_usd': 987.61,
    'today_pnl_usd': -12.39,
    'today_trades': 13,
    'win_rate': 33.33,
    'run_id': 'run-abc',
    'pending_txs': 1,
  });

  test('stream frame keeps today_trades from REST', () {
    // The stream omits today_trades; dropping it would show "0 trades today".
    final merged = rest.mergedWithStream({
      'type': 'state',
      'state': 'running',
      'equity_usd': 991.14,
      'open_positions': 0,
      'pending_txs': 0,
    });
    expect(merged.todayTrades, 13);
    expect(merged.equityUsd, 991.14);
    expect(merged.openPositions, 0);
    expect(merged.pendingTxs, 0);
    expect(merged.runId, 'run-abc');
  });

  test('stream frame still overrides the fields it does send', () {
    final merged = rest.mergedWithStream({
      'type': 'state',
      'state': 'stopped',
      'scanning': false,
      'tokens_scanned': 50,
      'opportunities': 37,
      'open_positions': 1,
      'today_pnl_usd': -8.86,
      'win_rate': 30.77,
    });
    expect(merged.state, BotState.stopped);
    expect(merged.scanning, isFalse);
    expect(merged.opportunities, 37);
    expect(merged.todayPnlUsd, -8.86);
    expect(merged.winRate, 30.77);
  });

  test('a null win_rate in the stream clears the previous value', () {
    expect(rest.mergedWithStream({'win_rate': null}).winRate, isNull);
  });

  test('an empty stream frame is a no-op', () {
    expect(rest.mergedWithStream({}).todayTrades, 13);
  });
}
// --- Invalid payload handling -------------------------------------------
// Corrupt data must not be coerced to 0 and rendered as a plausible balance.
void invalidPayloadTests() {
  test('a non-numeric equity is rejected instead of becoming 0', () {
    expect(
      () => Portfolio.fromJson({'equity_usd': 'not-a-number'}),
      throwsA(isA<PayloadFormatException>()),
    );
  });

  test('the rejection carries a message a user can act on', () {
    try {
      Portfolio.fromJson({'equity_usd': 'not-a-number'});
      fail('expected a PayloadFormatException');
    } on PayloadFormatException catch (e) {
      expect(e.field, 'equity_usd');
      expect(e.userMessage, contains('Unable to update trading data'));
      expect(e.userMessage, contains('retry'));
    }
  });

  test('null and numeric strings stay lenient', () {
    // The backend legitimately omits fields; only genuinely unusable values fail.
    final p = Portfolio.fromJson({'equity_usd': null, 'cash_usd': '900.5'});
    expect(p.equityUsd, 0);
    expect(p.cashUsd, 900.5);
  });

  test('a non-numeric open_positions is rejected', () {
    expect(
      () => BotStatus.fromJson({'open_positions': 'many'}),
      throwsA(isA<PayloadFormatException>()),
    );
  });

  test('a non-numeric scanned counter is rejected', () {
    expect(
      () => OpportunityList.fromJson({'scanned': 'lots'}),
      throwsA(isA<PayloadFormatException>()),
    );
  });
}