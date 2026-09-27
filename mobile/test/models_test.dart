import 'package:flutter_test/flutter_test.dart';
import 'package:memetrader_app/core/theme.dart';
import 'package:memetrader_app/models/models.dart';

void main() {
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
