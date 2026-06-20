import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Auto-update service
/// Kiểm tra phiên bản mới từ GitHub Releases và tải APK cập nhật
class UpdateService {
  // ═══ CẤU HÌNH ═══
  // Đổi owner/repo thành GitHub repo của bạn
  static const String githubOwner = 'trongkhiem194';
  static const String githubRepo = 'khle-tv';
  static const String currentVersion = '1.1.11';

  static const String _apiUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Kiểm tra cập nhật và hiện dialog nếu có bản mới
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final res = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'KhleTV/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final data = json.decode(res.body);
      final latestVersion = (data['tag_name'] ?? '').toString().replaceAll('v', '');
      final releaseNotes = data['body'] ?? '';

      if (latestVersion.isEmpty || latestVersion == currentVersion) return;

      // So sánh version
      if (!_isNewer(latestVersion, currentVersion)) return;

      // Tìm APK trong assets
      String? apkUrl;
      final assets = data['assets'] as List? ?? [];
      for (final asset in assets) {
        final name = asset['name']?.toString() ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url']?.toString();
          break;
        }
      }

      if (apkUrl == null || !context.mounted) return;

      // Hiện dialog cập nhật
      _showUpdateDialog(context, latestVersion, releaseNotes, apkUrl);
    } catch (e) {
      debugPrint('[Update] Check failed: $e');
    }
  }

  /// So sánh version: "1.1.0" > "1.0.0"
  static bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (l.length < 3) {
      l.add(0);
    }
    while (c.length < 3) {
      c.add(0);
    }
    for (int i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  /// Dialog thông báo cập nhật
  static void _showUpdateDialog(BuildContext context, String version, String notes, String apkUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(version: version, notes: notes, apkUrl: apkUrl),
    );
  }
}

/// Dialog cập nhật với progress bar tải APK
class _UpdateDialog extends StatefulWidget {
  final String version;
  final String notes;
  final String apkUrl;
  const _UpdateDialog({required this.version, required this.notes, required this.apkUrl});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  Future<void> _downloadAndInstall() async {
    setState(() { _downloading = true; _status = 'Đang tải APK...'; });

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(widget.apkUrl));
      request.headers.set('User-Agent', 'KhleTV/1.0');
      final response = await request.close();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/KhleTV_${widget.version}.apk');
      final sink = file.openWrite();

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() {
            _progress = receivedBytes / totalBytes;
            _status = 'Đang tải: ${(receivedBytes / 1024 / 1024).toStringAsFixed(1)} MB / ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB';
          });
        }
      }

      await sink.close();
      client.close();

      if (!mounted) return;
      setState(() => _status = 'Đang cài đặt...');

      // Mở file APK để cài đặt
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        setState(() { _downloading = false; _status = 'Lỗi: $e'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF15151F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE50914).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.system_update, color: Color(0xFFE50914), size: 24),
        ),
        const SizedBox(width: 12),
        const Text('Cập nhật mới!', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('v${widget.version}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2ECC71))),
          ),
          const SizedBox(height: 12),
          if (widget.notes.isNotEmpty)
            Text(widget.notes, style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5), maxLines: 6, overflow: TextOverflow.ellipsis),
          if (_downloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFE50914)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ],
      ),
      actions: [
        if (!_downloading) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Để sau', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            onPressed: _downloadAndInstall,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Cập nhật', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ],
    );
  }
}
