import 'package:flutter/material.dart';
import '../services/fshare_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  String _status = 'Đang khởi động...';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    _animCtrl.forward();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    setState(() => _status = 'Đang đăng nhập Fshare...');
    final ok = await FshareService.autoLogin();

    if (!mounted) return;

    if (ok) {
      setState(() => _status = 'Đăng nhập thành công!');
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D15),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFFF6B35)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 2)],
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              // App name
              RichText(
                text: const TextSpan(children: [
                  TextSpan(text: 'Kh.le', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
                  TextSpan(text: ' TV', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFE50914))),
                ]),
              ),
              const SizedBox(height: 8),
              Text('Rạp Phim Fshare', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 40),
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFE50914))),
              const SizedBox(height: 16),
              Text(_status, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
        ),
      ),
    );
  }
}
