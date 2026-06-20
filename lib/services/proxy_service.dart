import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Máy chủ Proxy đa luồng cục bộ
/// Giúp chia nhỏ file video từ Fshare thành từng chunk 3MB và tải song song tối đa 3 kết nối cùng lúc
class FshareParallelProxy {
  static HttpServer? _server;
  static int? _port;
  static final http.Client _client = http.Client();

  /// Khởi động máy chủ Proxy ngầm trên cổng ngẫu nhiên khả dụng
  static Future<int> start() async {
    if (_server != null) return _port!;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      _server!.listen((HttpRequest request) {
        if (request.uri.path == '/stream') {
          _handleStream(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      }, onError: (e) {
        debugPrint('[Proxy] Server error: $e');
      });

      debugPrint('[Proxy] Server started on port $_port');
      return _port!;
    } catch (e) {
      debugPrint('[Proxy] Failed to bind server: $e');
      return 0;
    }
  }

  /// Tắt máy chủ proxy
  static Future<void> stop() async {
    try {
      await _server?.close(force: true);
      _server = null;
      _port = null;
      debugPrint('[Proxy] Server stopped.');
    } catch (e) {
      debugPrint('[Proxy] Error stopping server: $e');
    }
  }

  /// Chuyển đổi link Fshare gốc thành link proxy cục bộ
  static String getProxyUrl(String originalUrl) {
    if (_port == null) return originalUrl;
    final encodedUrl = Uri.encodeComponent(originalUrl);
    return 'http://127.0.0.1:$_port/stream?url=$encodedUrl';
  }

  /// Xử lý stream truyền dữ liệu đa luồng
  static Future<void> _handleStream(HttpRequest request) async {
    final originalUrlStr = request.uri.queryParameters['url'];
    if (originalUrlStr == null || originalUrlStr.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final originalUrl = Uri.parse(originalUrlStr);

    // Phân tích header Range được gửi từ trình phát phim
    int startByte = 0;
    int? endByte;
    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        startByte = int.parse(match.group(1)!);
        final endStr = match.group(2);
        if (endStr != null && endStr.isNotEmpty) {
          endByte = int.parse(endStr);
        }
      }
    }

    debugPrint('[Proxy] Stream request start: byte=$startByte');

    try {
      // 1. Gửi request nhỏ ban đầu để lấy Content-Length và Content-Type từ máy chủ Fshare
      final initialRes = await _client.send(
        http.Request('GET', originalUrl)
          ..headers['Range'] = 'bytes=$startByte-${startByte + 1}',
      );

      final contentType = initialRes.headers['content-type'] ?? 'video/mp4';
      final contentRange = initialRes.headers['content-range'];
      int totalLength = 0;

      if (contentRange != null) {
        final totalMatch = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (totalMatch != null) {
          totalLength = int.parse(totalMatch.group(1)!);
        }
      }

      if (totalLength == 0) {
        totalLength = int.tryParse(initialRes.headers['content-length'] ?? '0') ?? 0;
      }

      // Hủy stream kiểm tra ban đầu ngay lập tức để giải phóng connection
      try {
        await initialRes.stream.listen((_) {}).cancel();
      } catch (_) {}

      // Nếu không lấy được dung lượng file, fall back về tải trực tiếp từ Fshare
      if (totalLength == 0) {
        debugPrint('[Proxy] Cannot get length. Fallback to direct download.');
        final fallReq = http.Request('GET', originalUrl);
        if (rangeHeader != null) fallReq.headers['Range'] = rangeHeader;
        final fallRes = await _client.send(fallReq);
        request.response.statusCode = fallRes.statusCode;
        fallRes.headers.forEach((k, v) => request.response.headers.set(k, v));
        await request.response.addStream(fallRes.stream);
        await request.response.close();
        return;
      }

      endByte ??= totalLength - 1;
      final responseLength = endByte - startByte + 1;

      // Thiết lập các header 206 Partial Content phản hồi cho player
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $startByte-$endByte/$totalLength');
      request.response.headers.set(HttpHeaders.contentLengthHeader, responseLength.toString());

      // Cấu hình tải đa luồng song song
      const int chunkSize = 3 * 1024 * 1024; // Mỗi chunk 3MB
      const int maxParallel = 3; // 3 luồng tải song song đồng thời từ Fshare

      int currentPos = startByte;
      final Map<int, Future<Uint8List?>> activeChunks = {};
      final List<http.Client> activeClients = [];
      bool clientDisconnected = false;

      // Lắng nghe sự kiện player ngắt kết nối (ví dụ khi tua phim, đóng trình phát)
      request.response.done.then((_) {
        clientDisconnected = true;
        final clients = List<http.Client>.from(activeClients);
        for (final c in clients) {
          try {
            c.close();
          } catch (_) {}
        }
      }).catchError((_) {
        clientDisconnected = true;
        final clients = List<http.Client>.from(activeClients);
        for (final c in clients) {
          try {
            c.close();
          } catch (_) {}
        }
      });

      // Hàm tải độc lập một chunk dữ liệu
      Future<Uint8List?> downloadChunk(int chunkStart) async {
        if (clientDisconnected) return null;

        final chunkEnd = (chunkStart + chunkSize - 1).clamp(0, endByte!);
        if (chunkStart > chunkEnd) return null;

        final chunkClient = http.Client();
        activeClients.add(chunkClient);

        try {
          final chunkReq = http.Request('GET', originalUrl)
            ..headers['Range'] = 'bytes=$chunkStart-$chunkEnd';
          final chunkRes = await chunkClient.send(chunkReq);

          if (chunkRes.statusCode == 200 || chunkRes.statusCode == 206) {
            final bytes = await chunkRes.stream.toBytes();
            activeClients.remove(chunkClient);
            chunkClient.close();
            return bytes;
          }
        } catch (_) {
          // Bắt lỗi kết nối bị hủy khi Client đóng
        } finally {
          activeClients.remove(chunkClient);
          chunkClient.close();
        }
        return null;
      }

      // Khởi chạy đợt tải song song đầu tiên cho 3 chunk
      for (int i = 0; i < maxParallel; i++) {
        final pos = startByte + i * chunkSize;
        if (pos <= endByte) {
          activeChunks[pos] = downloadChunk(pos);
        }
      }

      // Phục vụ dữ liệu tuần tự sang player qua Stream
      while (currentPos <= endByte && !clientDisconnected) {
        final currentChunkFuture = activeChunks[currentPos];
        if (currentChunkFuture == null) break;

        final data = await currentChunkFuture;
        activeChunks.remove(currentPos);

        if (clientDisconnected) break;

        if (data == null || data.isEmpty) {
          // Lỗi tải chunk, thử lại đúng chunk đó
          debugPrint('[Proxy] Chunk retry at $currentPos');
          final retryData = await downloadChunk(currentPos);
          if (clientDisconnected) break;
          if (retryData == null || retryData.isEmpty) {
            debugPrint('[Proxy] Terminating stream due to chunk failure.');
            break;
          }
          request.response.add(retryData);
        } else {
          request.response.add(data);
        }

        // Tự động đẩy cửa sổ trượt lên, kích hoạt tải trước chunk tiếp theo trong hàng đợi
        final nextPreloadPos = currentPos + maxParallel * chunkSize;
        if (nextPreloadPos <= endByte) {
          activeChunks[nextPreloadPos] = downloadChunk(nextPreloadPos);
        }

        currentPos += chunkSize;
      }

      await request.response.close();
      debugPrint('[Proxy] Stream completed for byte: $startByte');
    } catch (e) {
      debugPrint('[Proxy] Stream handler error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}
