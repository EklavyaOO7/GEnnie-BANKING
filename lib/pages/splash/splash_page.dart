import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' show intentChannel, handleDeepLink, bioAuthThenRegister;

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = Tween<double>(begin: 1, end: 0).animate(_ctrl);

    // warm-start: app in bg, new intent arrives
    intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onIntent') handleDeepLink(call.arguments as String?);
    });

    _checkDeepLinkThenNavigate();
  }

  Future<void> _checkDeepLinkThenNavigate() async {
    // flutterReady returns the pending deep link directly (null if none)
    String? raw;
    try { raw = await intentChannel.invokeMethod<String>('flutterReady'); } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    await _ctrl.forward();
    if (!mounted) return;

    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['host'] == 'register') {
          await bioAuthThenRegister(data['branchID'] as String, data['token'] as String);
          return;
        }
      } catch (_) {}
    }
    context.go('/home');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A6FA8), Color(0xFF329AD6), Color(0xFF5BB8F0)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 130, height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 32),
                      BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 4),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/images/app-new-icon.png', width: 100, height: 100, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('BankingGenie',
                    style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800,
                        letterSpacing: -0.5, shadows: [Shadow(color: Colors.black26, blurRadius: 8)])),
                const SizedBox(height: 6),
                Text('Your AI Banking Assistant',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 32),
                const _PulseDots(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseDots extends StatefulWidget {
  const _PulseDots();
  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 600)));
    _anims = _ctrls.map((c) => Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () { if (mounted) _ctrls[i].repeat(reverse: true); });
    }
  }

  @override
  void dispose() { for (final c in _ctrls) {
    c.dispose();
  } super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _anims[i],
        builder: (_, _) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: _anims[i].value),
          ),
        ),
      )),
    );
  }
}
