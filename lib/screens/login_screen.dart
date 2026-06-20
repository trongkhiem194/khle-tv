import 'package:flutter/material.dart';
import '../services/fshare_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePass = true;

  // Focus nodes — dùng trực tiếp cho TextField, KHÔNG bọc Focus thêm
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();
  final FocusNode _loginBtnFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Lắng nghe focus thay đổi để rebuild UI (viền đỏ)
    _emailFocus.addListener(() => setState(() {}));
    _passFocus.addListener(() => setState(() {}));
    _loginBtnFocus.addListener(() => setState(() {}));

    // Auto-focus vào email khi mở screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _loginBtnFocus.dispose();
    super.dispose();
  }

  void _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Vui lòng nhập đầy đủ email và mật khẩu');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await FshareService.login(email, pass);

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() { _loading = false; _error = result['error']; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D15),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF15151F),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFFF6B35)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              RichText(text: const TextSpan(children: [
                TextSpan(text: 'Kh.le', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                TextSpan(text: ' TV', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFE50914))),
              ])),
              const SizedBox(height: 8),
              Text('Đăng nhập bằng tài khoản Fshare', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 32),

              // ═══ EMAIL — TextField trực tiếp, không bọc Focus ═══
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _emailFocus.hasFocus ? const Color(0xFFE50914) : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: _emailFocus.hasFocus
                      ? [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.3), blurRadius: 12)]
                      : [],
                ),
                child: TextField(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email Fshare',
                    labelStyle: TextStyle(color: _emailFocus.hasFocus ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.email_outlined, color: _emailFocus.hasFocus ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.4)),
                    filled: true,
                    fillColor: _emailFocus.hasFocus ? const Color(0xFF252540) : const Color(0xFF1C1C30),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
              ),
              const SizedBox(height: 16),

              // ═══ PASSWORD — TextField trực tiếp ═══
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _passFocus.hasFocus ? const Color(0xFFE50914) : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: _passFocus.hasFocus
                      ? [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.3), blurRadius: 12)]
                      : [],
                ),
                child: TextField(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  obscureText: _obscurePass,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    labelStyle: TextStyle(color: _passFocus.hasFocus ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.lock_outline, color: _passFocus.hasFocus ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.4)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: Colors.white30),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    filled: true,
                    fillColor: _passFocus.hasFocus ? const Color(0xFF252540) : const Color(0xFF1C1C30),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    _loginBtnFocus.requestFocus();
                    _login();
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFF4444), fontSize: 13)),
                ),

              // ═══ LOGIN BUTTON ═══
              SizedBox(
                width: double.infinity,
                height: 48,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _loginBtnFocus.hasFocus ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: _loginBtnFocus.hasFocus
                        ? [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.6), blurRadius: 16)]
                        : [],
                  ),
                  child: ElevatedButton(
                    focusNode: _loginBtnFocus,
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _loginBtnFocus.hasFocus ? const Color(0xFFFF2020) : const Color(0xFFE50914),
                      disabledBackgroundColor: const Color(0xFF8B0000),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: _loginBtnFocus.hasFocus ? 8 : 2,
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            _loginBtnFocus.hasFocus ? '▶  Đăng nhập' : 'Đăng nhập',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Text('Cần tài khoản Fshare VIP để xem phim', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),

              // D-pad hint
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  '🎮  ▲▼ di chuyển  •  OK chọn ô nhập  •  Gõ chữ trên bàn phím',
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
