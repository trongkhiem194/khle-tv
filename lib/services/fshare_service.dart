import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fshare Service - Login, resolve link, list folder
/// Dùng Fshare API để stream phim trực tiếp
class FshareService {
  static const String _appKey = 'O5UTCpIlQez7xCjdzXzKDR+tAEnV51PosWxXIouT';
  static const String _userAgent = 'kodivietmediaf-K58W6U';
  static const String _apiBase = 'https://api.fshare.vn/api';

  static String? _token;
  static String? _sessionId;
  static String? _email;

  static bool get isLoggedIn => _token != null && _sessionId != null;
  static String? get email => _email;

  // ── Headers ──
  static Map<String, String> get _authHeaders => {
    'User-Agent': _userAgent,
    'Content-Type': 'application/json',
    'Cookie': 'session_id=${_sessionId ?? ''}',
  };

  // ══════════════════════════════════════
  //  LOGIN / LOGOUT
  // ══════════════════════════════════════

  /// Đăng nhập Fshare
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/user/login/'),
        headers: {
          'User-Agent': _userAgent,
          'cache-control': 'no-cache',
        },
        body: json.encode({
          'app_key': _appKey,
          'user_email': email,
          'password': password,
        }),
      );

      final data = json.decode(res.body);

      if (res.statusCode == 200 && data['token'] != null && data['session_id'] != null) {
        _token = data['token'];
        _sessionId = data['session_id'];
        _email = email;

        // Lưu credentials
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fshare_token', _token!);
        await prefs.setString('fshare_session', _sessionId!);
        await prefs.setString('fshare_email', email);
        await prefs.setString('fshare_password', password);

        return {'success': true, 'email': email};
      } else {
        return {'success': false, 'error': data['msg'] ?? 'Email hoặc mật khẩu không đúng'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  /// Đăng xuất
  static Future<void> logout() async {
    _token = null;
    _sessionId = null;
    _email = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fshare_token');
    await prefs.remove('fshare_session');
    await prefs.remove('fshare_email');
    await prefs.remove('fshare_password');
  }

  /// Tự động login từ credentials đã lưu
  static Future<bool> autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('fshare_email');
      final password = prefs.getString('fshare_password');

      if (email == null || password == null) return false;

      final result = await login(email, password);
      return result['success'] == true;
    } catch (e) {
      debugPrint('Auto-login failed: $e');
      return false;
    }
  }

  /// Kiểm tra session còn sống không
  static Future<bool> checkSession() async {
    if (_sessionId == null) return false;
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/user/get'),
        headers: {'User-Agent': _userAgent, 'Cookie': 'session_id=$_sessionId'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['code'] != 201; // 201 = not logged in
      }
      return false;
    } catch (_) {
      return true; // Network error → giữ session
    }
  }

  /// Lấy profile user
  static Future<Map<String, dynamic>> getProfile() async {
    if (_sessionId == null) return {'error': 'Chưa đăng nhập'};
    final res = await http.get(
      Uri.parse('$_apiBase/user/get'),
      headers: {'User-Agent': _userAgent, 'Cookie': 'session_id=$_sessionId'},
    );
    return json.decode(res.body);
  }

  // ══════════════════════════════════════
  //  RESOLVE LINK → DIRECT URL
  // ══════════════════════════════════════

  /// Resolve link Fshare → direct download/stream URL
  /// [linkcode] là mã file trên Fshare (vd: JBPA38OGX5IVNBDN)
  static Future<String?> resolveLink(String linkcode) async {
    if (!isLoggedIn) {
      final ok = await autoLogin();
      if (!ok) return null;
    }

    try {
      final res = await http.post(
        Uri.parse('$_apiBase/session/download'),
        headers: _authHeaders,
        body: json.encode({
          'zipflag': 0,
          'url': 'https://www.fshare.vn/file/$linkcode',
          'token': _token,
        }),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final location = data['location'];
        if (location != null && location.toString().isNotEmpty) {
          return location.toString();
        }
        debugPrint('Resolve failed: ${data['msg']}');
      } else if (res.statusCode == 201 || res.statusCode == 401) {
        // Session hết hạn → re-login
        final ok = await autoLogin();
        if (ok) return resolveLink(linkcode); // Retry
      }
    } catch (e) {
      debugPrint('Resolve error: $e');
    }
    return null;
  }

  // ══════════════════════════════════════
  //  LIST FOLDER
  // ══════════════════════════════════════

  /// Liệt kê file trong folder Fshare
  /// Trả về danh sách {name, linkcode, size, isVideo, isFolder}
  static Future<List<Map<String, dynamic>>> listFolder(String linkcode) async {
    if (!isLoggedIn) {
      final ok = await autoLogin();
      if (!ok) return [];
    }

    try {
      final res = await http.post(
        Uri.parse('$_apiBase/fileops/getFolderList'),
        headers: _authHeaders,
        body: json.encode({
          'token': _token,
          'url': 'https://www.fshare.vn/folder/$linkcode',
          'dirOnly': 0,
          'pageIndex': 0,
          'limit': 99999,
        }),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final items = data is List ? data : (data['items'] ?? []);

        const videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.ts', '.m4v'];
        const subExts = ['.srt', '.ass', '.ssa', '.vtt', '.sub'];

        return (items as List).map<Map<String, dynamic>>((item) {
          final name = item['name']?.toString() ?? 'Unknown';
          final isFolder = item['type']?.toString() == '0';
          final isVideo = !isFolder && videoExts.any((ext) => name.toLowerCase().endsWith(ext));
          final isSub = !isFolder && subExts.any((ext) => name.toLowerCase().endsWith(ext));
          final sizeBytes = int.tryParse(item['size']?.toString() ?? '0') ?? 0;

          return {
            'name': name,
            'linkcode': item['linkcode']?.toString() ?? item['id']?.toString() ?? '',
            'size': sizeBytes,
            'sizeFormatted': _formatSize(sizeBytes),
            'isFolder': isFolder,
            'isVideo': isVideo,
            'isSub': isSub,
          };
        }).toList();
      } else if (res.statusCode == 201 || res.statusCode == 401) {
        final ok = await autoLogin();
        if (ok) return listFolder(linkcode);
      }
    } catch (e) {
      debugPrint('List folder error: $e');
    }
    return [];
  }

  // ── Helper: Format file size ──
  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i > 1 ? 2 : 0)} ${units[i]}';
  }
}
