import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Phantom Connect: nonce from backend -> sign locally -> verify -> JWT.
///
/// The private key is generated on-device, kept in memory, and never sent to
/// the backend. This is a devnet stand-in for the in-app browser wallet.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _seedController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connecting = state.auth == AuthStatus.connecting;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.accent),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MemeTrader', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('AI trading engine v2.4', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
              'CONNECT WALLET',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            const Text(
              'Sign the backend nonce to authenticate. Your key stays on this '
              'device - it is never uploaded.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _seedController,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: _obscure ? 1 : 3,
              minLines: 1,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Wallet recovery phrase (12 or 24 words)',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ActionButton(
              label: 'CONNECT',
              icon: Icons.link_rounded,
              onPressed: connecting
                  ? () async {}
                  : () async {
                      final phrase = _seedController.text.trim();
                      if (phrase.split(RegExp(r'\s+')).length < 12) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid 12-word recovery phrase')),
                        );
                        return;
                      }
                      final ok = await state.signInWithSeedPhrase(phrase);
                      if (ok) _seedController.clear();
                    },
            ),
            if (connecting) ...[
              const SizedBox(height: 20),
              const Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
            if (state.authError != null) ...[
              const SizedBox(height: 16),
              Text(
                state.authError!,
                style: const TextStyle(color: AppTheme.offline, fontSize: 12, height: 1.4),
              ),
            ],
            if (AppConfig.allowDevWallet) ...[
              const SectionLabel('Quick start'),
              ActionButton(
                label: 'USE DEV WALLET',
                icon: Icons.bolt_rounded,
                outlined: true,
                onPressed: connecting ? noop : state.signInWithDevWallet,
              ),
              const SizedBox(height: 8),
              const Text(
                'Generates a throwaway devnet key in the browser so you can test '
                'paper trading without a Phantom extension. Debug builds only.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
              ),
            ],
            const SectionLabel('Paper mode'),
            const SectionCard(
              child: Row(
                children: [
                  Icon(Icons.shield_rounded, size: 18, color: AppTheme.live),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No funds move until you explicitly enable live execution. '
                      'Paper trading is the default.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Backend'),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API endpoint',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConfig.apiBaseUrl,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: AppConfig.apiBaseUrl)),
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('Copy endpoint', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
