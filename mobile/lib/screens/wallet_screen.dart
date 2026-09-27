import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Reference layout:
///   USDC WALLET 0x43bb...73e0 / AVAILABLE BALANCE $550,161.79
///   +12.38%  +$80,153.22  /  [Deposit] [Withdraw]
///   USDC $550,164.38  /  AI trading engine v2.4 LIVE
///   1 in trade  PnL +$2,347,325.96  /  [STOP TRADING BOT]  /  AI LOG
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final portfolio = state.portfolio;
    final bot = state.botStatus;
    final isLive = state.isLive;

    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshAll();
        await state.refreshLogs();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _WalletHeader(state: state, portfolio: portfolio),
          const SizedBox(height: 18),
          _BalanceBlock(
            portfolio: portfolio,
            isLive: isLive,
            usdcBalance: state.wallet?.balanceUsdc,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: 'Deposit',
                  icon: Icons.add_rounded,
                  outlined: true,
                  onPressed: () async => _showPaperOnlySheet(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  label: 'Withdraw',
                  icon: Icons.north_east_rounded,
                  outlined: true,
                  onPressed: () async => _showPaperOnlySheet(context),
                ),
              ),
            ],
          ),
          const SectionLabel('Engine'),
          _EngineCard(state: state, isLive: isLive, bot: bot),
          const SizedBox(height: 16),
          ActionButton(
            label: isLive ? 'STOP TRADING BOT' : 'START TRADING BOT',
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
                : state.closeAll,
          ),
          const SectionLabel('AI Log'),
          _AiLogPanel(state: state),
        ],
      ),
    );
  }

  void _showPaperOnlySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('On-chain transfers are not part of V1', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            SizedBox(height: 10),
            Text(
              'This build is non-custodial: the app never moves your funds. '
              'Deposit and Withdraw arrive in a later release, and only for '
              'real mainnet trading.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.state, required this.portfolio});

  final AppState state;
  final Portfolio portfolio;

  @override
  Widget build(BuildContext context) {
    final address = state.walletAddress ?? state.wallet?.walletAddress ?? '';
    final sol = state.wallet?.balanceSol;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'USDC WALLET',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                  ),
                  const SizedBox(width: 8),
                  LivePill(isLive: state.isSignedIn && sol != null, label: state.isSignedIn ? 'LINKED' : 'OFFLINE'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                address.isEmpty ? 'not connected' : shortenAddress(address),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: state.refreshAll,
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 20),
        ),
      ],
    );
  }
}

class _BalanceBlock extends StatelessWidget {
  const _BalanceBlock({
    required this.portfolio,
    required this.isLive,
    required this.usdcBalance,
  });

  final Portfolio portfolio;
  final bool isLive;
  final double? usdcBalance;

  @override
  Widget build(BuildContext context) {
    final usd = usdcBalance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AVAILABLE BALANCE',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
        ),
        const SizedBox(height: 6),
        Text(
          formatUsd(portfolio.availableUsd),
          style: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              formatPct(portfolio.allTimePnlPct),
              style: TextStyle(color: pnlColor(portfolio.allTimePnlUsd), fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Text(
              formatSignedUsd(portfolio.allTimePnlUsd),
              style: TextStyle(color: pnlColor(portfolio.allTimePnlUsd), fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (usd != null) ...[
          const SizedBox(height: 18),
          SectionCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.accent,
                  child: Text('\$', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Text('USDC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isLive ? AppTheme.live : AppTheme.textPrimary)),
                const Spacer(),
                Text(
                  formatUsd(usd),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({required this.state, required this.isLive, required this.bot});

  final AppState state;
  final bool isLive;
  final BotStatus? bot;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 18, color: AppTheme.accent),
            const SizedBox(width: 8),
            const Text('AI trading engine v2.4', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            LivePill(isLive: isLive),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            state.isPaperMode ? 'Paper mode - no real funds at risk' : 'LIVE execution enabled',
            style: TextStyle(color: state.isPaperMode ? AppTheme.warning : AppTheme.offline, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            StatTile(
              label: 'In trade',
              value: '${state.openPositions.length}',
              hint: state.isScanning ? 'scanning...' : 'idle',
            ),
            StatTile(
              label: 'Unrealised P&L',
              value: formatSignedUsd(state.portfolio.unrealizedPnlUsd),
              valueColor: pnlColor(state.portfolio.unrealizedPnlUsd),
            ),
            StatTile(
              label: 'Today',
              value: formatSignedUsd(state.portfolio.todayPnlUsd),
              valueColor: pnlColor(state.portfolio.todayPnlUsd),
            ),
          ],
        ),
        if (bot != null && bot!.pendingTxs > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${bot!.pendingTxs} transaction${bot!.pendingTxs == 1 ? '' : 's'} waiting for wallet approval',
                  style: const TextStyle(color: AppTheme.warning, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _AiLogPanel extends StatelessWidget {
  const _AiLogPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final logs = state.logs;
    if (logs.isEmpty) {
      return const SectionCard(
        child: EmptyState(
          icon: Icons.terminal_rounded,
          message: 'No engine activity yet',
          subtitle: 'Start the bot and decisions will stream here in real time.',
        ),
      );
    }
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final log in logs.take(30))
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                log.isWarning ? Icons.warning_amber_rounded : Icons.chevron_right_rounded,
                size: 16,
                color: log.isWarning ? AppTheme.warning : AppTheme.textMuted,
              ),
              title: Text(
                log.message,
                style: TextStyle(fontSize: 12, color: log.isWarning ? AppTheme.warning : AppTheme.textPrimary),
              ),
              subtitle: Text(
                log.createdAt == null ? log.category : DateFormat('HH:mm:ss').format(log.createdAt!),
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
