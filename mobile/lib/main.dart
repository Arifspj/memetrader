import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MemeTraderApp());
}

class MemeTraderApp extends StatefulWidget {
  const MemeTraderApp({super.key});

  @override
  State<MemeTraderApp> createState() => _MemeTraderAppState();
}

class _MemeTraderAppState extends State<MemeTraderApp> {
  final AppState _state = AppState();
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _state.restoreSession().then((_) {
      if (mounted) setState(() => _restoring = false);
    });
    _state.refreshHealth();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: _state,
      child: MaterialApp(
        title: 'MemeTrader',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: _restoring
            ? const _SplashScreen()
            : Consumer<AppState>(
                builder: (context, state, _) => state.isSignedIn
                    ? const AppShell()
                    : const AuthScreen(),
              ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 40, color: AppTheme.accent),
          SizedBox(height: 18),
          SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    ),
  );
}
