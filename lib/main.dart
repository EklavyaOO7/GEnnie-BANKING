import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/splash/splash_page.dart';
import 'pages/home/home_page.dart';
import 'pages/history/history_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/register/register_page.dart';
import 'core/services/biometric_service.dart';

const intentChannel = MethodChannel('com.kiya.bankinggenie/intent');

// Global notifier so settings page can trigger a theme rebuild
final themeNotifier = ValueNotifier<String>('light');

Future<void> handleDeepLink(String? raw) async {
  if (raw == null) return;
  try {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['host'] == 'register') {
      await bioAuthThenRegister(data['branchID'] as String, data['token'] as String);
    }
  } catch (_) {}
}

Future<void> bioAuthThenRegister(String branchID, String token) async {
  final prefs = await SharedPreferences.getInstance();
  final bioEnabled = prefs.getBool('biometric_enabled') ?? true;
  if (bioEnabled) {
    final result = await BiometricService().authenticate();
    if (result != 'success' && result != 'unavailable') return; // auth cancelled/failed
  }
  _router.go('/register', extra: {'branchID': branchID, 'token': token});
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('ViewInsets cannot be negative')) return;
    FlutterError.presentError(details);
  };
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value = prefs.getString('app_theme') ?? 'light';
  runApp(const BankingGenieApp());
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/home', builder: (context, state) => const AuthGate()),
      GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          final extra = (state.extra as Map<String, dynamic>?) ?? {};
          return RegisterPage(
            branchID: extra['branchID'] as String? ?? '',
            token: extra['token'] as String? ?? '',
          );
        },
      ),
    ],
  );
}

final _router = _buildRouter();

class BankingGenieApp extends StatelessWidget {
  const BankingGenieApp({super.key});

  static ThemeData _buildTheme(String key) {
    const themes = {
      'light':  (bg: Color(0xFFF0F6FF), primary: Color(0xFF329AD6), secondary: Color(0xFF1A6FA8), surface: Color(0xFFFFFFFF), onSurface: Color(0xFF0F172A), appBar: Color(0xFFFFFFFF)),
      'dark':   (bg: Color(0xFF0F172A), primary: Color(0xFF329AD6), secondary: Color(0xFF60A5FA), surface: Color(0xFF1E293B), onSurface: Color(0xFFF1F5F9), appBar: Color(0xFF1E293B)),
      'green':  (bg: Color(0xFFF0FFF4), primary: Color(0xFF16A34A), secondary: Color(0xFF15803D), surface: Color(0xFFFFFFFF), onSurface: Color(0xFF0F172A), appBar: Color(0xFFFFFFFF)),
      'purple': (bg: Color(0xFFF5F3FF), primary: Color(0xFF7C3AED), secondary: Color(0xFF6D28D9), surface: Color(0xFFFFFFFF), onSurface: Color(0xFF0F172A), appBar: Color(0xFFFFFFFF)),
      'slate':  (bg: Color(0xFFF8FAFC), primary: Color(0xFF475569), secondary: Color(0xFF334155), surface: Color(0xFFFFFFFF), onSurface: Color(0xFF0F172A), appBar: Color(0xFFFFFFFF)),
    };
    final t = themes[key] ?? themes['light']!;
    final isDark = key == 'dark';
    return (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
      scaffoldBackgroundColor: t.bg,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: t.primary,
        secondary: t.secondary,
        surface: t.surface,
        onSurface: t.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.appBar,
        foregroundColor: t.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: themeNotifier,
      builder: (_, themeKey, __) => MaterialApp.router(
        title: 'BankingGenie',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(themeKey),
        routerConfig: _router,
      ),
    );
  }
}

// ── Biometric auth gate wrapping HomePage
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _bio = BiometricService();
  // null = still checking pref, false = unlocked, true = locked
  bool? _locked;
  bool _authFailed = false;

  @override
  void initState() {
    super.initState();
    _triggerAuth();
  }

  Future<void> _triggerAuth() async {
    if (mounted) setState(() { _locked = null; _authFailed = false; });
    final prefs = await SharedPreferences.getInstance();
    final bioEnabled = prefs.getBool('biometric_enabled') ?? true;
    if (!bioEnabled) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    final result = await _bio.authenticate();
    if (!mounted) return;
    setState(() {
      _locked = (result != 'success' && result != 'unavailable');
      _authFailed = _locked!;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Still reading pref — show nothing (avoids fingerprint flash when disabled)
    if (_locked == null) return Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor);
    if (_locked == false) return const HomePage();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), blurRadius: 20)],
              ),
              child: Icon(Icons.fingerprint, color: Theme.of(context).colorScheme.primary, size: 44),
            ),
            const SizedBox(height: 24),
            Text(
              _authFailed ? 'Authentication cancelled' : 'Verifying your identity...',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
            ),
            if (_authFailed) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _triggerAuth,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
