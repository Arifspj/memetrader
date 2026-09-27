import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/ws_client.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SectionLabel('Wallet'),
        SectionCard(
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 20, color: AppTheme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.walletAddress == null ? 'Not connected' : shortenAddress(state.walletAddress!),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.wallet?.walletAddress == null
                          ? 'Connect a wallet to trade'
                          : 'On-chain ${shortenAddress(state.wallet!.walletAddress)}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Execution'),
        SectionCard(
          child: Column(
            children: [
              _Row(
                icon: Icons.science_rounded,
                label: 'Mode',
                value: state.executionMode.toUpperCase(),
                valueColor: state.isPaperMode ? AppTheme.warning : AppTheme.offline,
              ),
              _Row(
                icon: Icons.account_balance_rounded,
                label: 'Starting capital',
                value: formatUsd(state.risk.startingCapitalUsd),
              ),
              _Row(
                icon: Icons.trending_up_rounded,
                label: 'Total trades',
                value: '${state.portfolio.totalTrades}',
                last: true,
              ),
            ],
          ),
        ),
        const SectionLabel('System status'),
        SectionCard(
          child: Column(
            children: [
              ValueListenableBuilder<WsStatus>(
                valueListenable: state.wsConnection,
                builder: (context, status, _) => _Row(
                  icon: Icons.podcasts_rounded,
                  label: 'Realtime feed',
                  value: switch (status) {
                    WsStatus.connected => 'CONNECTED',
                    WsStatus.connecting => 'CONNECTING',
                    WsStatus.reconnecting => 'RECONNECTING',
                    WsStatus.offline => 'OFFLINE',
                  },
                  valueColor: status == WsStatus.connected ? AppTheme.live : AppTheme.warning,
                ),
              ),
              _Row(
                icon: Icons.dns_rounded,
                label: 'API',
                value: state.health.isEmpty ? 'UNKNOWN' : (state.health['status']?.toString().toUpperCase() ?? 'UNKNOWN'),
                valueColor: state.connectionError == null ? AppTheme.live : AppTheme.offline,
              ),
              _Row(
                icon: Icons.hub_rounded,
                label: 'Chain',
                value: state.health['chain']?.toString().toUpperCase() ?? 'DEVNET',
              ),
              _Row(
                icon: Icons.link_rounded,
                label: 'Endpoint',
                value: Uri.parse(state.health.isEmpty ? '' : '${state.health['host'] ?? ''}').host.isEmpty
                    ? 'not reachable'
                    : Uri.parse('${state.health['host']}').host,
                last: true,
              ),
            ],
          ),
        ),
        if (state.connectionError != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.offline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.connectionError!,
                    style: const TextStyle(color: AppTheme.offline, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SectionLabel('Account'),
        SectionCard(
          child: Column(
            children: [
              _Row(
                icon: Icons.tune_rounded,
                label: 'Risk settings',
                value: 'backend managed',
              ),
              _Row(
                icon: Icons.settings_rounded,
                label: 'Settings',
                value: 'v1',
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ActionButton(
          label: 'LOGOUT',
          icon: Icons.logout_rounded,
          outlined: true,
          color: AppTheme.offline,
          onPressed: state.signOut,
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'v0.1.0 - paper trading MVP',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: AppTheme.border)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    ),
  );
}
