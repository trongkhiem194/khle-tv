import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Máy chủ Proxy chạy trên Isolate riêng biệt để tránh đơ giao diện điều khiển (UI Thread)
/// Tải song song tối ưu và hỗ trợ Backpressure tự động khi tạm dừng (Pause) video
class FshareParallelProxy {
  static Isolate? _isolate;
  static ReceivePort? _receivePort;
  static int? _port;

  /// Khởi động máy chủ Proxy trên Isolate riêng biệt
  static Future<int> start() async {
    if (_isolate != null) return _port!;

    try {
      _receivePort = ReceivePort();
      
      // Spawn isolate để chạy HTTP Server
      _isolate = await Isolate.spawn(
        _proxyIsolateMain,
        _receivePort!.sendPort,
        debugName: 'FshareProxyIsolate',
      );

      final completer = Completer<int>();
      _receivePort!.listen((message) {
        if (message is int) {
          _port = message;
          completer.complete(message);
        }
      });

      return completer.future;
    } catch (e) {
      debugPrint('[Proxy] Failed to start proxy isolate: $e');
      return 0;
    }
  }

  /// Tắt máy chủ proxy và giải phóng Isolate
  static Future<void> stop() async {
    try {
      _isolate?.kill(priority: Isolate.beforeNextEvent);
      _isolate = null;
      _receivePort?.close();
      _receivePort = null;
      _port = null;
      debugPrint('[Proxy] Isolate stopped.');
    } catch (e) {
      debugPrint('[Proxy] Error stopping isolate: $e');
    }
  }

  /// Helper lấy địa chỉ IP LAN hiện tại của thiết bị (Wifi hoặc Ethernet)
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
    return '127.0.0.1'; // Fallback
  }

  /// Chuyển đổi link Fshare gốc thành link proxy cục bộ
  static String getProxyUrl(String originalUrl, String ip) {
    if (_port == null) return originalUrl;
    final encodedUrl = Uri.encodeComponent(originalUrl);
    return 'http://$ip:$_port/stream?url=$encodedUrl';
  }

  /// Entrypoint chính chạy trong Isolate riêng
  static void _proxyIsolateMain(SendPort mainSendPort) async {
    // Áp dụng HTTP Override chỉ trong Isolate này
    HttpOverrides.global = IPv4HttpOverrides();

    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      mainSendPort.send(server.port);

      await for (final HttpRequest request in server) {
        if (request.uri.path == '/stream') {
          _handleStream(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      }
    } catch (e) {
      debugPrint('[ProxyIsolate] Error: $e');
      mainSendPort.send(0);
    }
  }

  /// Xử lý request stream từ trình phát phim
  static Future<void> _handleStream(HttpRequest request) async {
    final originalUrlStr = request.uri.queryParameters['url'];
    if (originalUrlStr == null || originalUrlStr.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final originalUrl = Uri.parse(originalUrlStr);

    // Phân tích range header
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

    final Map<String, String> upstreamHeaders = {};
    request.headers.forEach((name, values) {
      if (name.toLowerCase() != 'host') {
        upstreamHeaders[name] = values.join(', ');
      }
    });

    if (!upstreamHeaders.containsKey('user-agent') && !upstreamHeaders.containsKey('User-Agent')) {
      upstreamHeaders['User-Agent'] = 'Mozilla/5.0';
    }

    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      // Gửi probe request ban đầu để lấy thông tin content length
      final probeReq = await client.openUrl('GET', originalUrl).timeout(const Duration(seconds: 10));
      upstreamHeaders.forEach((k, v) => probeReq.headers.set(k, v));
      probeReq.headers.set('Range', 'bytes=$startByte-${startByte + 1}');

      final probeRes = await probeReq.close().timeout(const Duration(seconds: 10));
      final contentType = probeRes.headers.value(HttpHeaders.contentTypeHeader) ?? 'video/mp4';
      final contentRange = probeRes.headers.value(HttpHeaders.contentRangeHeader);
      int totalLength = 0;

      if (contentRange != null) {
        final totalMatch = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (totalMatch != null) {
          totalLength = int.parse(totalMatch.group(1)!);
        }
      }

      if (totalLength == 0) {
        totalLength = int.tryParse(probeRes.headers.value(HttpHeaders.contentLengthHeader) ?? '0') ?? 0;
      }

      try {
        await probeRes.listen((_) {}).cancel();
      } catch (_) {}

      // Nếu lỗi hoặc không lấy được độ dài, chuyển tiếp trực tiếp (direct fall back)
      if (totalLength == 0 || probeRes.statusCode >= 400) {
        debugPrint('[ProxyIsolate] Direct fallback. Status: ${probeRes.statusCode}');
        final directReq = await client.openUrl('GET', originalUrl).timeout(const Duration(seconds: 10));
        upstreamHeaders.forEach((k, v) => directReq.headers.set(k, v));
        if (rangeHeader != null) directReq.headers.set('Range', rangeHeader);

        final directRes = await directReq.close().timeout(const Duration(seconds: 10));
        request.response.statusCode = directRes.statusCode;
        directRes.headers.forEach((k, v) => request.response.headers.set(k, v.join(', ')));

        await request.response.addStream(directRes);
        await request.response.close();
        return;
      }

      endByte ??= totalLength - 1;
      final responseLength = endByte - startByte + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $startByte-$endByte/$totalLength');
      request.response.headers.set(HttpHeaders.contentLengthHeader, responseLength.toString());

      // Phục vụ dữ liệu bằng Stream hỗ trợ tự động Backpressure
      final chunkStream = _getChunkStream(originalUrl, startByte, endByte, upstreamHeaders);
      await request.response.addStream(chunkStream);
      await request.response.close();
    } catch (e) {
      debugPrint('[ProxyIsolate] Connection handler error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      client.close();
    }
  }

  /// Generator Stream tải chunk 3MB với cơ chế tải trước tối đa 1 chunk và tự động tạm dừng theo backpressure
  static Stream<List<int>> _getChunkStream(
    Uri originalUrl,
    int startByte,
    int endByte,
    Map<String, String> upstreamHeaders,
  ) async* {
    const int chunkSize = 3 * 1024 * 1024; // 3MB chunk
    int currentPos = startByte;

    Future<List<int>?>? nextChunkFuture;

    // Helper tải một chunk
    Future<List<int>?> downloadChunk(int chunkStart) async {
      final chunkEnd = (chunkStart + chunkSize - 1).clamp(0, endByte);
      if (chunkStart > chunkEnd) return null;

      final client = HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 8);

      try {
        final req = await client.openUrl('GET', originalUrl).timeout(const Duration(seconds: 10));
        upstreamHeaders.forEach((k, v) => req.headers.set(k, v));
        req.headers.set('Range', 'bytes=$chunkStart-$chunkEnd');

        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 200 || res.statusCode == 206) {
          final builder = BytesBuilder();
          await res.timeout(const Duration(seconds: 12)).forEach((data) {
            builder.add(data);
          });
          return builder.takeBytes();
        }
      } catch (e) {
        debugPrint('[ProxyIsolate] Chunk download failed at $chunkStart: $e');
      } finally {
        client.close();
      }
      return null;
    }

    // Tải trước chunk đầu tiên
    nextChunkFuture = downloadChunk(currentPos);

    while (currentPos <= endByte) {
      List<int>? data = await nextChunkFuture;

      // Bắt đầu tải chunk tiếp theo song song ngay trước khi yield
      final nextPos = currentPos + chunkSize;
      if (nextPos <= endByte) {
        nextChunkFuture = downloadChunk(nextPos);
      }

      if (data == null || data.isEmpty) {
        debugPrint('[ProxyIsolate] Chunk retry at $currentPos');
        data = await downloadChunk(currentPos);
        if (data == null || data.isEmpty) {
          debugPrint('[ProxyIsolate] Chunk failed twice. Terminating stream.');
          break;
        }
      }

      yield data;
      currentPos += chunkSize;
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
          }
        } catch (_) {}
      }

      if (isHttps) {
        return await SecureSocket.startConnect(
          connectHost,
          targetPort,
          onBadCertificate: (cert) => true,
        );
      } else {
        return await Socket.startConnect(connectHost, targetPort);
      }
    };
    return client;
  }
}
