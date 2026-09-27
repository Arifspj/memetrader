import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// AI OPPORTUNITIES - live scan output from the backend.
class TradeScreen extends StatelessWidget {
  const TradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final opportunities = state.opportunities;
    final actionable = opportunities.where((o) => !o.isBlocked).toList();
    final blocked = opportunities.where((o) => o.isBlocked).toList();

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: opportunities.isEmpty
          ? ListView(
              children: [
                SectionCard(
                  child: EmptyState(
                    icon: Icons.radar_rounded,
                    message: state.isScanning ? 'Scanning Solana pairs...' : 'No opportunities yet',
                    subtitle: state.isScanning
                        ? 'The scanner is running. New pairs appear here automatically.'
                        : 'Start the bot on the AI tab to begin scanning.',
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _Header(count: actionable.length, scanning: state.isScanning),
                for (final o in actionable) _OpportunityCard(opportunity: o),
                if (blocked.isNotEmpty) ...[
                  const SectionLabel('Rejected by safety filters'),
                  for (final o in blocked) _OpportunityCard(opportunity: o),
                ],
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.scanning});

  final int count;
  final bool scanning;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'AI OPPORTUNITIES',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
        ),
        LivePill(isLive: scanning, label: scanning ? 'SCANNING' : 'IDLE'),
        const SizedBox(width: 10),
        Text(
          '$count',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.accent),
        ),
      ],
    ),
  );
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final o = opportunity;
    final momentum = o.part('momentum') ?? o.buySellRatio;
    final safety = o.part('safety');
    final volume = o.part('volume') ?? o.volume5m;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${o.symbol}/USDC',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                StatusTag(
                  text: o.isBlocked ? 'REJECTED' : (o.isBuying ? 'BUYING' : 'WATCHING'),
                  color: o.isBlocked
                      ? AppTheme.offline
                      : (o.isBuying ? AppTheme.live : AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              o.dexId.isEmpty ? 'Solana DEX' : o.dexId.toUpperCase(),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 0.5),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: StatTile(label: 'AI Score', value: o.score.toStringAsFixed(0), valueColor: o.score >= 80 ? AppTheme.live : AppTheme.textPrimary)),
                Expanded(child: StatTile(label: 'Liquidity', value: formatCompactUsd(o.liquidityUsd))),
                Expanded(
                  child: StatTile(
                    label: 'Momentum',
                    value: momentum.toStringAsFixed(0),
                    valueColor: pnlColor(momentum),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ScoreBar(score: o.score),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.show_chart_rounded, size: 13, color: AppTheme.textMuted),
                const SizedBox(width: 5),
                Text('Price ${formatPrice(o.priceUsd)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(width: 14),
                const Icon(Icons.bar_chart_rounded, size: 13, color: AppTheme.textMuted),
                const SizedBox(width: 5),
                Text('Vol5m ${formatCompactUsd(volume)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                if (safety != null) ...[
                  const SizedBox(width: 14),
                  const Icon(Icons.verified_user_rounded, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 5),
                  Text('Safety ${safety.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ],
            ),
            if (o.isBlocked) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.offline.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  o.blockedReasons.join(' - '),
                  style: const TextStyle(color: AppTheme.offline, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
