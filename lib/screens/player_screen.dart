import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class PlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String fileName;

  const PlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.fileName = '',
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  String? _error;

  List<AudioTrack> _audioTracks = [];
  List<SubtitleTrack> _subtitleTracks = [];

  final List<StreamSubscription> _subs = [];

  late final FocusNode _backgroundFocusNode;
  late final FocusNode _playPauseFocusNode;

  Timer? _seekDebounceTimer;
  bool _isSeeking = false;
  Duration _seekPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _backgroundFocusNode = FocusNode();
    _playPauseFocusNode = FocusNode();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    WakelockPlus.enable();
    _initPlayer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32MB buffer
      ),
    );

    // Cấu hình giải mã phần cứng & đệm tương thích cao, tránh giật lag RAM trên TV Box
    if (_player.platform is NativePlayer) {
      try {
        final nativePlayer = _player.platform as NativePlayer;
        // Sử dụng mediacodec để giải mã trực tiếp lên màn hình (Direct Hardware Decoding)
        nativePlayer.setProperty('hwdec', 'mediacodec');
        nativePlayer.setProperty('vd-lavc-dr', 'yes');
        // Giới hạn buffer demuxer ở mức 64MiB để tối ưu cho Chromecast 4K
        nativePlayer.setProperty('demuxer-max-bytes', '64MiB');
        nativePlayer.setProperty('demuxer-max-back-bytes', '16MiB');
        nativePlayer.setProperty('cache', 'yes');
        nativePlayer.setProperty('cache-secs', '45'); // Buffer trước 45 giây

        // ═══ Tối ưu hóa nâng cao cho TV Box & Chromecast 4K ═══
        nativePlayer.setProperty('tls-verify', 'no'); // Bỏ qua xác thực TLS giúp tải luồng phim nhanh hơn
        nativePlayer.setProperty('audio-channels', 'stereo'); // Ép downmix về Stereo trong decoder để tiết kiệm CPU
        nativePlayer.setProperty('sub-ass-override', 'yes'); // Loại bỏ định dạng phụ đề ASS phức tạp, chuyển về dạng chữ phẳng đơn giản
        nativePlayer.setProperty('cache-pause-initial-skip', 'yes'); // Không dừng khựng chờ tải đầy bộ đệm ban đầu

        debugPrint("[Player] Custom Native Player properties (mediacodec, 64MiB buffer & TV optimizations) configured.");
      } catch (e) {
        debugPrint("[Player] Error setting Native Player properties: $e");
      }
    }

    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _subs.add(_player.stream.position.listen((p) {
      if (mounted && !_isSeeking) setState(() => _position = p);
    }));
    _subs.add(_player.stream.duration.listen((d) { if (mounted) setState(() => _duration = d); }));
    _subs.add(_player.stream.playing.listen((p) { if (mounted) setState(() => _playing = p); }));
    _subs.add(_player.stream.buffering.listen((b) { if (mounted) setState(() => _buffering = b); }));
    _subs.add(_player.stream.error.listen((e) { if (mounted && e.isNotEmpty) setState(() => _error = e); }));
    _subs.add(_player.stream.tracks.listen((t) {
      if (mounted) setState(() { _audioTracks = t.audio; _subtitleTracks = t.subtitle; });
    }));

    _player.open(Media(widget.videoUrl, httpHeaders: {'User-Agent': 'Mozilla/5.0'}));
    _startHideTimer();
  }

  @override
  void dispose() {
    _backgroundFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _seekDebounceTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onSliderChanged(double v) {
    _hideTimer?.cancel();
    if (!_isSeeking) {
      setState(() => _isSeeking = true);
    }
    
    final targetMs = (v * _duration.inMilliseconds).round();
    setState(() {
      _seekPosition = Duration(milliseconds: targetMs);
    });

    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _player.seek(_seekPosition);
      if (mounted) {
        setState(() {
          _position = _seekPosition;
          _isSeeking = false;
        });
        _startHideTimer();
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _playing) {
        setState(() => _controlsVisible = false);
        _backgroundFocusNode.requestFocus();
      }
    });
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      Future.microtask(() {
        if (mounted) {
          _playPauseFocusNode.requestFocus();
        }
      });
    }
    _startHideTimer();
  }

  void _togglePlayPause() { _player.playOrPause(); _showControls(); }

  void _seekRelative(int seconds) {
    _showControls();
    _hideTimer?.cancel();
    if (!_isSeeking) {
      setState(() {
        _isSeeking = true;
        _seekPosition = _position;
      });
    }

    final n = _seekPosition + Duration(seconds: seconds);
    setState(() {
      _seekPosition = n < Duration.zero ? Duration.zero : (n > _duration ? _duration : n);
    });

    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _player.seek(_seekPosition);
      if (mounted) {
        setState(() {
          _position = _seekPosition;
          _isSeeking = false;
        });
        _startHideTimer();
      }
    });
  }

  // ═══ Audio Track Dialog ═══
  void _showAudioDialog() {
    _hideTimer?.cancel();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF15151F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.audiotrack, color: Color(0xFFE50914), size: 24),
        SizedBox(width: 8),
        Text('Kênh Âm Thanh', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18)),
      ]),
      content: SizedBox(
        width: 350,
        child: _audioTracks.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: Text('Không có kênh âm thanh khác', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              shrinkWrap: true,
              itemCount: _audioTracks.length,
              itemBuilder: (_, i) {
                final t = _audioTracks[i];
                final label = t.title ?? t.language ?? 'Track ${i + 1}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: const Color(0xFF1C1C30),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () { _player.setAudioTrack(t); Navigator.pop(ctx); _startHideTimer(); },
                      focusColor: const Color(0xFFE50914).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          const Icon(Icons.audiotrack, color: Color(0xFFE50914), size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15))),
                          if (t.language != null) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFE50914).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                            child: Text(t.language!, style: const TextStyle(fontSize: 12, color: Color(0xFFE50914), fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
      ),
      actions: [
        TextButton(
          onPressed: () { Navigator.pop(ctx); _startHideTimer(); },
          child: const Text('Đóng', style: TextStyle(color: Colors.white38, fontSize: 14)),
        ),
      ],
    ));
  }

  // ═══ Subtitle Dialog ═══
  void _showSubDialog() {
    _hideTimer?.cancel();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF15151F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.subtitles, color: Color(0xFF3B82F6), size: 24),
        SizedBox(width: 8),
        Text('Phụ Đề', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18)),
      ]),
      content: SizedBox(
        width: 350,
        child: ListView(shrinkWrap: true, children: [
          // Tắt sub
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: const Color(0xFF1C1C30),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () { _player.setSubtitleTrack(SubtitleTrack.no()); Navigator.pop(ctx); _startHideTimer(); },
                focusColor: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Icon(Icons.subtitles_off, color: Colors.white54, size: 20),
                    SizedBox(width: 12),
                    Text('Tắt phụ đề', style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ]),
                ),
              ),
            ),
          ),
          ..._subtitleTracks.asMap().entries.map((e) {
            final t = e.value;
            final label = t.title ?? t.language ?? 'Sub ${e.key + 1}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFF1C1C30),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () { _player.setSubtitleTrack(t); Navigator.pop(ctx); _startHideTimer(); },
                  focusColor: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      const Icon(Icons.subtitles, color: Color(0xFF3B82F6), size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15))),
                      if (t.language != null) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                        child: Text(t.language!, style: const TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          }),
          if (_subtitleTracks.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Video không có phụ đề nhúng', style: TextStyle(color: Colors.white38, fontSize: 14))),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () { Navigator.pop(ctx); _startHideTimer(); },
          child: const Text('Đóng', style: TextStyle(color: Colors.white38, fontSize: 14)),
        ),
      ],
    ));
  }

  String _fmt(Duration d) {
    final h = d.inHours; final m = d.inMinutes.remainder(60); final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: true,
        child: Focus(
          focusNode: _backgroundFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;

            // Back keys
            if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.browserBack) {
              if (_controlsVisible) {
                setState(() => _controlsVisible = false);
                _backgroundFocusNode.requestFocus();
              } else {
                Navigator.pop(context);
              }
              return KeyEventResult.handled;
            }

            // Khi controls ẩn → bắt key tua / play / hiện controls
            if (!_controlsVisible) {
              if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
                _togglePlayPause();
                return KeyEventResult.handled;
              } else if (key == LogicalKeyboardKey.arrowLeft) {
                _seekRelative(-10);
                return KeyEventResult.handled;
              } else if (key == LogicalKeyboardKey.arrowRight) {
                _seekRelative(10);
                return KeyEventResult.handled;
              } else {
                _showControls();
                return KeyEventResult.handled;
              }
            } else {
              // Khi controls hiện → để D-pad tự do di chuyển giữa các InkWell, chỉ bắt media keys
              
              // Nếu nút Play/Pause đang có focus, xử lý phím Trái/Phải để tua trực tiếp và phím Xuống để ẩn controls
              if (_playPauseFocusNode.hasFocus) {
                if (key == LogicalKeyboardKey.arrowLeft) {
                  _seekRelative(-10);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  _seekRelative(10);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  setState(() => _controlsVisible = false);
                  _backgroundFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
              }

              if (key == LogicalKeyboardKey.mediaPlayPause) {
                _togglePlayPause();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.mediaPlay) {
                _player.play();
                _showControls();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.mediaPause) {
                _player.pause();
                _showControls();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.mediaRewind) {
                _seekRelative(-10);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.mediaFastForward) {
                _seekRelative(10);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () {
              if (_controlsVisible) {
                _togglePlayPause();
              } else {
                _showControls();
              }
            },
            child: Stack(fit: StackFit.expand, children: [
              // Video
              Center(child: Video(controller: _videoController, controls: NoVideoControls)),

              // Buffering
              if (_buffering) const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),

              // Error
              if (_error != null) Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('⚠️', style: TextStyle(fontSize: 48, decoration: TextDecoration.none)),
                const SizedBox(height: 12),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(_error!, style: const TextStyle(color: Colors.white54, fontSize: 13, decoration: TextDecoration.none), textAlign: TextAlign.center)),
                const SizedBox(height: 20),
                Material(color: Colors.transparent, child: InkWell(
                  onTap: () { setState(() => _error = null); _player.open(Media(widget.videoUrl)); },
                  focusColor: const Color(0xFFE50914).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Thử lại', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                )),
              ])),

              // ═══ CONTROLS ═══
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: ExcludeFocus(
                    excluding: !_controlsVisible,
                    child: Container(
                      color: Colors.black45,
                      child: Column(children: [
                        // ── TOP BAR ──
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
                          child: SafeArea(bottom: false, child: Row(children: [
                            // Back
                            Material(color: Colors.transparent, child: InkWell(
                              onTap: () => Navigator.pop(context),
                              focusColor: const Color(0xFFE50914).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(24)),
                                child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                              ),
                            )),
                            const SizedBox(width: 16),
                            // Title
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, decoration: TextDecoration.none), overflow: TextOverflow.ellipsis),
                                if (widget.fileName.isNotEmpty) Text(widget.fileName, style: const TextStyle(fontSize: 12, color: Colors.white54, decoration: TextDecoration.none), overflow: TextOverflow.ellipsis),
                              ],
                            )),
                            const SizedBox(width: 8),
                            // ═══ AUDIO BUTTON ═══
                            Material(color: Colors.transparent, child: InkWell(
                              onTap: _showAudioDialog,
                              focusColor: const Color(0xFFE50914).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(24)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.audiotrack, color: Colors.white, size: 20),
                                  if (_audioTracks.length > 1) ...[
                                    const SizedBox(width: 6),
                                    Text('${_audioTracks.length}', style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                                  ],
                                ]),
                              ),
                            )),
                            const SizedBox(width: 8),
                            // ═══ SUBTITLE BUTTON ═══
                            Material(color: Colors.transparent, child: InkWell(
                              onTap: _showSubDialog,
                              focusColor: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(24)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.subtitles, color: Colors.white, size: 20),
                                  if (_subtitleTracks.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text('${_subtitleTracks.length}', style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                                  ],
                                ]),
                              ),
                            )),
                          ])),
                        ),

                        const Spacer(),

                        // ── CENTER: Play/Seek buttons ──
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Material(color: Colors.transparent, child: InkWell(
                            onTap: () => _seekRelative(-10),
                            canRequestFocus: false,
                            focusColor: Colors.white24, borderRadius: BorderRadius.circular(32),
                            child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(32)),
                              child: const Icon(Icons.replay_10, color: Colors.white, size: 40)),
                          )),
                          const SizedBox(width: 36),
                          Material(color: Colors.transparent, child: InkWell(
                            focusNode: _playPauseFocusNode,
                            onTap: _togglePlayPause,
                            focusColor: const Color(0xFFE50914).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(44),
                            child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
                              color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(44),
                              boxShadow: [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.5), blurRadius: 24)]),
                              child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 52)),
                          )),
                          const SizedBox(width: 36),
                          Material(color: Colors.transparent, child: InkWell(
                            onTap: () => _seekRelative(10),
                            canRequestFocus: false,
                            focusColor: Colors.white24, borderRadius: BorderRadius.circular(32),
                            child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(32)),
                              child: const Icon(Icons.forward_10, color: Colors.white, size: 40)),
                          )),
                        ]),

                        const Spacer(),

                        // ── BOTTOM: Seek bar ──
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                          child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SliderTheme(
                              data: SliderThemeData(
                                thumbColor: _isSeeking ? const Color(0xFFE50914) : Colors.transparent,
                                activeTrackColor: _isSeeking ? const Color(0xFFE50914) : Colors.white30,
                                inactiveTrackColor: Colors.white12,
                                overlayColor: const Color(0xFFE50914).withValues(alpha: 0.2),
                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: _isSeeking ? 10 : 0),
                                trackHeight: _isSeeking ? 6 : 3,
                              ),
                              child: Slider(
                                focusNode: FocusNode(canRequestFocus: false),
                                value: _duration.inMilliseconds > 0
                                    ? ((_isSeeking ? _seekPosition : _position).inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                    : 0.0,
                                onChanged: _onSliderChanged,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(
                                '${_fmt(_isSeeking ? _seekPosition : _position)} / ${_fmt(_duration)}',
                                style: const TextStyle(fontSize: 14, color: Colors.white70, decoration: TextDecoration.none),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
                                child: const Text('◀ Tua lại  •  OK Dừng/Phát  •  ▶ Tua đi  •  ▲ Lên bảng điều khiển', style: TextStyle(fontSize: 11, color: Colors.white54, decoration: TextDecoration.none)),
                              ),
                            ]),
                          ])),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
