import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/ws_client.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ai_screen.dart';
import 'history_screen.dart';
import 'more_screen.dart';
import 'trade_screen.dart';
import 'wallet_screen.dart';

/// Five-tab shell: Wallet | Trade | AI | History | More
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = <_Tab>[
    _Tab('Wallet', Icons.account_balance_wallet_rounded, Icons.account_balance_wallet_outlined),
    _Tab('Trade', Icons.swap_horiz_rounded, Icons.swap_horiz_rounded),
    _Tab('AI', Icons.auto_awesome_rounded, Icons.auto_awesome_outlined),
    _Tab('History', Icons.receipt_long_rounded, Icons.receipt_long_outlined),
    _Tab('More', Icons.more_horiz_rounded, Icons.more_horiz_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: _buildAppBar(state),
      body: IndexedStack(
        index: _index,
        children: const [
          WalletScreen(),
          TradeScreen(),
          AiScreen(),
          HistoryScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final tab in _tabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar(AppState state) {
    if (_index != 0) return null;
    return AppBar(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: AppTheme.accent),
          SizedBox(width: 8),
          Text('MemeTrader'),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(child: _ConnectionPill(state: state)),
        ),
      ],
    );
  }
}

/// Header badge.
///
/// A stopped bot is not "offline" - red OFFLINE must mean the connection is
/// actually gone, otherwise a healthy idle session looks like a failure.
class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.wsConnection.value == WsStatus.connected;
    if (!connected) {
      return const LivePill(isLive: false, label: 'OFFLINE');
    }
    return LivePill(
      isLive: state.isLive,
      label: state.isLive ? 'LIVE' : 'IDLE',
      tone: state.isLive ? AppTheme.live : AppTheme.warning,
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
