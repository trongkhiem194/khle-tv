import 'package:flutter/material.dart';
import '../services/fshare_service.dart';
import '../services/update_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await FshareService.getProfile();
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111119),
        title: const Text('⚙️ Cài đặt', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Account info
          _card('👤 Tài khoản Fshare', [
            _row('Email', FshareService.email ?? 'N/A'),
            if (_profile != null) ...[
              _row('Loại', _profile!['account_type']?.toString() ?? 'N/A'),
              _row('Tên', _profile!['name']?.toString() ?? 'N/A'),
              if (_profile!['expire_vip'] != null)
                _row('VIP hết hạn', _formatExpire(_profile!['expire_vip'])),
            ] else if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE50914)))),
              ),
          ]),
          const SizedBox(height: 16),

          // App info
          _card('📱 Ứng dụng', [
            _row('Tên', 'Kh.le TV'),
            _row('Phiên bản', UpdateService.currentVersion),
            _row('Nguồn dữ liệu', 'VietmediaF + TMDB'),
            _row('Stream từ', 'Fshare VIP'),
          ]),
          const SizedBox(height: 16),

          // Logout button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await FshareService.logout();
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF15151F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  String _formatExpire(dynamic timestamp) {
    try {
      final ts = int.parse(timestamp.toString());
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return 'N/A';
    }
  }
}
