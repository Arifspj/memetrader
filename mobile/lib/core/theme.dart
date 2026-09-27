import 'package:flutter/material.dart';

/// Dark trading-desk design system, matched to the reference UI.
class AppTheme {
  const AppTheme._();

  static const Color bg = Color(0xFF0B0E11);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceAlt = Color(0xFF1C2128);
  static const Color border = Color(0xFF262D36);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  static const Color accent = Color(0xFF2F81F7);
  static const Color live = Color(0xFF3FB950);
  static const Color offline = Color(0xFFF85149);
  static const Color warning = Color(0xFFD29922);

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        surface: surface,
        primary: accent,
        error: offline,
      ),
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? accent : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? accent : textMuted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textMuted,
        indicatorColor: accent,
        dividerColor: border,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceAlt,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// `+12.38%` / `-$4.20` with the right colour.
Color pnlColor(double value) {
  if (value > 0) return AppTheme.live;
  if (value < 0) return AppTheme.offline;
  return AppTheme.textSecondary;
}

/// `550161.79` -> `550,161.79`, matching the reference UI.
String formatUsd(double value, {int decimals = 2}) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  return '$sign\$${_grouped(abs.toStringAsFixed(decimals))}';
}

String _grouped(String digits) {
  final dot = digits.indexOf('.');
  final whole = dot == -1 ? digits : digits.substring(0, dot);
  final rest = dot == -1 ? '' : digits.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '$buffer$rest';
}

String formatSignedUsd(double value, {int decimals = 2}) {
  final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
  return '$sign${formatUsd(value.abs(), decimals: decimals)}';
}

String formatPct(double value, {int decimals = 2}) {
  final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
  return '$sign${value.abs().toStringAsFixed(decimals)}%';
}

/// Meme-coin prices are tiny: $0.0000142 needs more than 2 decimals, and
/// trailing zeros only add noise.
String formatPrice(double value) {
  if (value == 0) return '\$0';
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';
  if (abs >= 1) return '$sign\$${_grouped(abs.toStringAsFixed(4))}';
  // 6 significant figures, no trailing zeros.
  final text = abs.toStringAsPrecision(6);
  final trimmed = text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
  return '$sign\$$trimmed';
}

String formatCompactUsd(double value) {
  final abs = value.abs();
  if (abs >= 1e9) return '\$${(value / 1e9).toStringAsFixed(2)}B';
  if (abs >= 1e6) return '\$${(value / 1e6).toStringAsFixed(2)}M';
  if (abs >= 1e3) return '\$${(value / 1e3).toStringAsFixed(1)}K';
  return formatUsd(value);
}

String shortenAddress(String address) {
  if (address.length <= 10) return address;
  return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
}
