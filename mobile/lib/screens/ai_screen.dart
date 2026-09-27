import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Control surface: START / STOP / CLOSE ALL plus live engine telemetry.
class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final bot = state.botStatus;
    final isLive = state.isLive;
    final risk = state.risk;

    return RefreshIndicator(
      onRefresh: state.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AI TRADING ENGINE',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                      ),
                    ),
                    LivePill(isLive: isLive, label: isLive ? 'LIVE' : 'STOPPED'),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mode: ${state.executionMode.toUpperCase()}',
                    style: TextStyle(
                      color: state.isPaperMode ? AppTheme.warning : AppTheme.offline,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Scanning',
                        value: '${bot?.tokensScanned ?? 0}',
                        hint: 'tokens',
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: 'Opportunities',
                        value: '${bot?.opportunities ?? state.opportunities.length}',
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: 'Open trades',
                        value: '${bot?.openPositions ?? state.openPositions.length}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "TODAY'S P&L",
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatSignedUsd(state.portfolio.todayPnlUsd),
                        style: TextStyle(
                          color: pnlColor(state.portfolio.todayPnlUsd),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${bot?.todayTrades ?? 0} trades today',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ActionButton(
            label: isLive ? 'STOP AI TRADING' : 'START AI TRADING',
            icon: isLive ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: isLive ? AppTheme.offline : AppTheme.live,
            onPressed: () => isLive ? state.stopBot() : state.startBot(),
          ),
          const SizedBox(height: 10),
          ActionButton(
            label: 'CLOSE ALL POSITIONS',
            icon: Icons.close_rounded,
            outlined: true,
            color: AppTheme.warning,
            onPressed: state.openPositions.isEmpty
                ? noop
                : () => _confirmCloseAll(context, state),
          ),
          const SizedBox(height: 12),
          const Text(
            'STOP halts new entries only. Open positions stay managed by the '
            'engine (TP / SL / trailing). CLOSE ALL exits every position now.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.45),
          ),
          const SectionLabel('Risk limits'),
          SectionCard(
            child: Column(
              children: [
                _RiskRow(label: 'Max positions', value: '${risk.maxOpenPositions}'),
                _RiskRow(label: 'Risk / trade', value: '${risk.riskPerTradePct.toStringAsFixed(1)}%'),
                _RiskRow(label: 'Daily loss limit', value: '${risk.maxDailyLossPct.toStringAsFixed(1)}%', danger: true),
                _RiskRow(label: 'Take profit', value: '+${risk.takeProfitPct.toStringAsFixed(1)}%'),
                _RiskRow(label: 'Stop loss', value: '-${risk.stopLossPct.toStringAsFixed(1)}%'),
                _RiskRow(label: 'Trailing activation', value: '+${risk.trailingActivationPct.toStringAsFixed(1)}%'),
                _RiskRow(label: 'Max hold', value: '${risk.maxHoldMinutes} min'),
                _RiskRow(label: 'Min entry score', value: risk.minEntryScore.toStringAsFixed(0), last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCloseAll(BuildContext context, AppState state) async {
    final count = state.openPositions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Close all positions?'),
        content: Text(
          '$count open position${count == 1 ? '' : 's'} will be exited at market. '
          'This is separate from STOP and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close all'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await state.closeAll();
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.label, required this.value, this.danger = false, this.last = false});

  final String label;
  final String value;
  final bool danger;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: AppTheme.border)),
    ),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: danger ? AppTheme.offline : AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
