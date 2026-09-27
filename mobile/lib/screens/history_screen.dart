import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Positions | All | Deposits | Withdrawals
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Trading history',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Positions'),
              Tab(text: 'All'),
              Tab(text: 'Deposits'),
              Tab(text: 'Withdrawals'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PositionsTab(state: state),
                _AllTab(state: state),
                const _TransfersTab(
                  title: 'No deposits yet',
                  subtitle: 'This V1 build is non-custodial, so there is no deposit flow.',
                ),
                const _TransfersTab(
                  title: 'No withdrawals yet',
                  subtitle: 'The app never moves funds on your behalf.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionsTab extends StatelessWidget {
  const _PositionsTab({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final positions = [...state.openPositions, ...state.closedPositions];
    if (positions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        message: 'No positions yet',
        subtitle: 'Trades opened by the engine will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: positions.length,
        itemBuilder: (context, i) => _PositionRow(position: positions[i]),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final pnl = p.isOpen ? p.unrealizedPnlUsd : (p.realizedPnlUsd ?? 0);
    final pnlPct = p.isOpen ? p.unrealizedPnlPct : 0.0;
    final when = p.openedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.symbol}/USDC',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                StatusTag(text: p.side, color: AppTheme.accent),
                const SizedBox(width: 6),
                StatusTag(
                  text: p.isOpen ? 'OPEN' : 'CLOSED',
                  color: p.isOpen ? AppTheme.live : AppTheme.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Entry',
                    value: formatPrice(p.entryPrice),
                    hint: when == null ? null : DateFormat('dd MMM HH:mm').format(when),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: p.isOpen ? 'Mark' : 'Exit',
                    value: formatPrice((p.isOpen ? p.currentPrice : p.exitPrice) ?? 0),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Qty',
                    value: p.qty.toStringAsPrecision(4),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'P&L',
                    value: formatSignedUsd(pnl),
                    valueColor: pnlColor(pnl),
                    hint: p.isOpen ? formatPct(pnlPct) : null,
                  ),
                ),
              ],
            ),
            if (p.takeProfit != null || p.stopLoss != null || p.exitReason != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (p.takeProfit != null)
                    _meta('TP', formatPrice(p.takeProfit!)),
                  if (p.stopLoss != null)
                    _meta('SL', formatPrice(p.stopLoss!)),
                  if (p.exitReason != null) _meta('Exit', p.exitReason!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label ', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
      Text(value, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
    ],
  );
}

class _AllTab extends StatelessWidget {
  const _AllTab({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final trades = state.trades;
    if (trades.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_vert_rounded,
        message: 'No trades yet',
        subtitle: 'Every buy and sell the engine executes is logged here.',
      );
    }
    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: trades.length,
        itemBuilder: (context, i) => _TradeRow(trade: trades[i]),
      ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final Trade trade;

  @override
  Widget build(BuildContext context) {
    final t = trade;
    final isBuy = t.isBuy;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (isBuy ? AppTheme.live : AppTheme.offline).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isBuy ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 17,
              color: isBuy ? AppTheme.live : AppTheme.offline,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${t.symbol}/USDC', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text(
                      isBuy ? 'BUY' : 'SELL',
                      style: TextStyle(
                        color: isBuy ? AppTheme.live : AppTheme.offline,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatUsd(t.usdAmount),
                    'at ${formatPrice(t.price)}',
                    t.mode.toUpperCase(),
                    if (t.createdAt != null) DateFormat('dd MMM HH:mm').format(t.createdAt!),
                  ].join(' - '),
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (t.pnlUsd != null)
            Text(
              formatSignedUsd(t.pnlUsd!),
              style: TextStyle(
                color: pnlColor(t.pnlUsd!),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _TransfersTab extends StatelessWidget {
  const _TransfersTab({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.account_balance_rounded,
    message: title,
    subtitle: subtitle,
  );
}
