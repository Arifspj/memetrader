import 'package:flutter/foundation.dart';

/// Backend connection settings.
///
/// Defaults to `localhost`, which is correct when the app runs in Chrome on the
/// same machine as the API. Override for other targets:
///
///   Android emulator : `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
///   Physical device  : `--dart-define=API_BASE_URL=http://your-lan-ip:8000`
///   Phone + tunnel   : `--dart-define=API_BASE_URL=https://subdomain.ngrok.io`
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static String get wsBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString();
  }

  /// Phantom deep link used by the "Open Phantom" affordance.
  static const String phantomDeepLink = 'https://phantom.app';

  /// A random throwaway devnet key can be generated from the login screen.
  /// Never available in release builds.
  static bool get allowDevWallet => kDebugMode;

  static const Duration requestTimeout = Duration(seconds: 15);
}
