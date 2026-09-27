import 'package:flutter/material.dart';

import '../core/theme.dart';

/// No-op for disabled actions.
Future<void> noop() async {}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.border),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// The green LIVE / red OFFLINE pill from the reference design.
///
/// [tone] exists because a stopped bot must not be painted like a broken
/// connection: default maps [isLive] to live/offline colours, while callers
/// that have three states (live / idle / offline) pass the middle one in.
class LivePill extends StatelessWidget {
  const LivePill({super.key, required this.isLive, this.label, this.tone});

  final bool isLive;
  final String? label;

  /// Overrides the colour implied by [isLive].
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? (isLive ? AppTheme.live : AppTheme.offline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label ?? (isLive ? 'LIVE' : 'OFFLINE'),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tag used for OPEN / CLOSED / LONG / SHORT in the history list.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.text, this.color = AppTheme.textSecondary});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.hint,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? hint;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: TextStyle(
          color: valueColor ?? AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (hint != null) ...[
        const SizedBox(height: 2),
        Text(hint!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    ],
  );
}

/// Thin progress bar for the 0-100 AI score.
class ScoreBar extends StatelessWidget {
  const ScoreBar({super.key, required this.score, this.height = 6});

  final double score;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colour = score >= 80
        ? AppTheme.live
        : score >= 60
        ? AppTheme.warning
        : AppTheme.offline;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: (score / 100).clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: AppTheme.surfaceAlt,
        valueColor: AlwaysStoppedAnimation(colour),
      ),
    );
  }
}

/// Inline banner for a failed or unusable backend response.
///
/// The engine's numbers must never silently show as zero after a bad response,
/// so the failure is stated in plain words on the screen the user is already
/// looking at. It disappears as soon as a clean snapshot lands.
class ConnectionErrorBanner extends StatelessWidget {
  const ConnectionErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.offline.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.offline.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.offline),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Unable to update trading data',
                style: TextStyle(
                  color: AppTheme.offline,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.subtitle});

  final IconData icon;
  final String message;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Wraps async actions with a busy state and surfaces errors as a snackbar.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.outlined = false,
  });

  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final Color? color;
  final bool outlined;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 18), const SizedBox(width: 8)],
              Text(widget.label),
            ],
          );

    return widget.outlined
        ? OutlinedButton(
            onPressed: _busy ? null : _run,
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.color ?? AppTheme.textPrimary,
              side: BorderSide(color: widget.color ?? AppTheme.border),
            ),
            child: child,
          )
        : FilledButton(
            onPressed: _busy ? null : _run,
            style: widget.color == null
                ? null
                : FilledButton.styleFrom(backgroundColor: widget.color),
            child: child,
          );
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
