import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Máy chủ Proxy đa luồng cục bộ
/// Giúp chia nhỏ file video từ Fshare thành từng chunk 3MB và tải song song tối đa 3 kết nối cùng lúc
class FshareParallelProxy {
  static HttpServer? _server;
  static int? _port;
  
  // Sử dụng HttpClient gốc với autoUncompress = false để tránh các lỗi nén gzip video của Fshare
  static final HttpClient _ioClient = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 15);

  /// Khởi động máy chủ Proxy ngầm trên cổng ngẫu nhiên khả dụng (bind 0.0.0.0 cho Android)
  static Future<int> start() async {
    if (_server != null) return _port!;

    try {
      // Bind to 0.0.0.0 (anyIPv4) để tránh các lỗi định tuyến loopback cục bộ trên Android
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
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

      debugPrint('[Proxy] Server started on port $_port (bound to anyIPv4)');
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

  /// Helper lấy địa chỉ IP LAN hiện tại của thiết bị (Wifi hoặc Ethernet) để TV kết nối không bị chặn loopback
  static Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            if (ip.isNotEmpty && ip != '127.0.0.1') {
              return ip;
            }
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1'; // Fallback nếu không có kết nối mạng
  }

  /// Chuyển đổi link Fshare gốc thành link proxy cục bộ sử dụng IP LAN
  static String getProxyUrl(String originalUrl, String ip) {
    if (_port == null) return originalUrl;
    final encodedUrl = Uri.encodeComponent(originalUrl);
    return 'http://$ip:$_port/stream?url=$encodedUrl';
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

    // Sao chép và chuyển tiếp toàn bộ header từ player sang Fshare (bao gồm Cookie, User-Agent)
    final Map<String, String> upstreamHeaders = {};
    request.headers.forEach((name, values) {
      if (name.toLowerCase() != 'host') {
        upstreamHeaders[name] = values.join(', ');
      }
    });

    // Đảm bảo luôn có User-Agent tiêu chuẩn để Fshare không chặn
    if (!upstreamHeaders.containsKey('user-agent') && !upstreamHeaders.containsKey('User-Agent')) {
      upstreamHeaders['User-Agent'] = 'Mozilla/5.0';
    }

    debugPrint('[Proxy] Connection received. Range: $rangeHeader. Forwarding headers: $upstreamHeaders');

    try {
      // 1. Gửi request nhỏ ban đầu để lấy Content-Length và Content-Type từ máy chủ Fshare
      final initialReq = await _ioClient.openUrl('GET', originalUrl).timeout(const Duration(seconds: 10));
      upstreamHeaders.forEach((k, v) => initialReq.headers.set(k, v));
      initialReq.headers.set('Range', 'bytes=$startByte-${startByte + 1}');

      debugPrint('[Proxy] Sending initial probe to: $originalUrl');
      final initialRes = await initialReq.close().timeout(const Duration(seconds: 10));
      debugPrint('[Proxy] Probe response status: ${initialRes.statusCode}. Headers: ${initialRes.headers}');

      final contentType = initialRes.headers.value(HttpHeaders.contentTypeHeader) ?? 'video/mp4';
      final contentRange = initialRes.headers.value(HttpHeaders.contentRangeHeader);
      int totalLength = 0;

      if (contentRange != null) {
        final totalMatch = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (totalMatch != null) {
          totalLength = int.parse(totalMatch.group(1)!);
        }
      }

      if (totalLength == 0) {
        totalLength = int.tryParse(initialRes.headers.value(HttpHeaders.contentLengthHeader) ?? '0') ?? 0;
      }

      // Hủy stream kiểm tra ban đầu ngay lập tức
      try {
        await initialRes.listen((_) {}).cancel();
      } catch (_) {}

      // Nếu không lấy được dung lượng file hoặc Fshare từ chối (403/400),
      // tiến hành truyền phát trực tiếp (Direct Forward) qua HTTP Client thông thường
      if (totalLength == 0 || initialRes.statusCode >= 400) {
        debugPrint('[Proxy] Falling back to direct forwarding. Status: ${initialRes.statusCode}');
        final fallReq = await _ioClient.openUrl('GET', originalUrl).timeout(const Duration(seconds: 10));
        upstreamHeaders.forEach((k, v) => fallReq.headers.set(k, v));
        if (rangeHeader != null) fallReq.headers.set('Range', rangeHeader);
        
        final fallRes = await fallReq.close().timeout(const Duration(seconds: 10));
        request.response.statusCode = fallRes.statusCode;
        fallRes.headers.forEach((k, v) => request.response.headers.set(k, v.join(', ')));
        
        await request.response.addStream(fallRes);
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
      final Map<int, Future<List<int>?>> activeChunks = {};
      final List<HttpClient> activeClients = [];
      bool clientDisconnected = false;

      // Lắng nghe sự kiện player ngắt kết nối
      request.response.done.then((_) {
        clientDisconnected = true;
        final clients = List<HttpClient>.from(activeClients);
        for (final c in clients) {
          try {
            c.close(force: true);
          } catch (_) {}
        }
      }).catchError((_) {
        clientDisconnected = true;
        final clients = List<HttpClient>.from(activeClients);
        for (final c in clients) {
          try {
            c.close(force: true);
          } catch (_) {}
        }
      });

      // Hàm tải độc lập một chunk dữ liệu sử dụng HttpClient thô (autoUncompress = false) và có timeout
      Future<List<int>?> downloadChunk(int chunkStart) async {
        if (clientDisconnected) return null;

        final chunkEnd = (chunkStart + chunkSize - 1).clamp(0, endByte!);
        if (chunkStart > chunkEnd) return null;

        final chunkClient = HttpClient()
          ..autoUncompress = false
          ..connectionTimeout = const Duration(seconds: 8);
        activeClients.add(chunkClient);

        try {
          final chunkReq = await chunkClient.openUrl('GET', originalUrl).timeout(const Duration(seconds: 10));
          upstreamHeaders.forEach((k, v) => chunkReq.headers.set(k, v));
          chunkReq.headers.set('Range', 'bytes=$chunkStart-$chunkEnd');

          final chunkRes = await chunkReq.close().timeout(const Duration(seconds: 10));
          if (chunkRes.statusCode == 200 || chunkRes.statusCode == 206) {
            final builder = BytesBuilder();
            // Đọc stream dữ liệu với timeout tối đa 15 giây
            await chunkRes.timeout(const Duration(seconds: 15)).forEach((data) {
              if (!clientDisconnected) {
                builder.add(data);
              }
            });
            activeClients.remove(chunkClient);
            chunkClient.close();
            return builder.takeBytes();
          }
        } catch (e) {
          debugPrint('[Proxy] downloadChunk error at $chunkStart: $e');
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

        // Tải trước chunk tiếp theo trong hàng đợi
        final nextPreloadPos = currentPos + maxParallel * chunkSize;
        if (nextPreloadPos <= endByte) {
          activeChunks[nextPreloadPos] = downloadChunk(nextPreloadPos);
        }

        currentPos += chunkSize;
      }

      await request.response.close();
      debugPrint('[Proxy] Stream completed successfully for byte: $startByte');
    } catch (e) {
      debugPrint('[Proxy] Stream handler error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}

/// Bộ Override HTTP ép kết nối qua IPv4 duy nhất cho tên miền Fshare
class IPv4HttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (Uri uri, String? host, int? port) async {
      final resolvedHost = host ?? uri.host;
      final targetPort = port ?? uri.port;
      final isHttps = uri.scheme == 'https';

      dynamic connectHost = resolvedHost;
      if (resolvedHost.contains('fshare.vn')) {
        try {
          final addresses = await InternetAddress.lookup(resolvedHost, type: InternetAddressType.IPv4);
          if (addresses.isNotEmpty) {
            connectHost = addresses.first;
            debugPrint('[IPv4Override] DNS lookup resolved $resolvedHost -> IPv4: ${addresses.first.address}');
          }
        } catch (e) {
          debugPrint('[IPv4Override] Failed to resolve IPv4 for $resolvedHost: $e');
        }
      }

      if (isHttps) {
        return await SecureSocket.startConnect(
          connectHost,
          targetPort,
          onBadCertificate: (cert) => true, // Bỏ qua do kết nối thẳng qua IP đã phân giải thủ công
        );
      } else {
        return await Socket.startConnect(connectHost, targetPort);
      }
    };
    return client;
  }
}

