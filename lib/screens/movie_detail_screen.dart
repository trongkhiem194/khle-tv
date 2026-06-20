import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/fshare_service.dart';
import 'player_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final int tmdbId;
  final String type; // 'movie' or 'tv'
  const MovieDetailScreen({super.key, required this.tmdbId, required this.type});
  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  Map<String, dynamic>? _detail;
  List<dynamic> _sources = [];
  bool _loading = true;
  bool _sourcesLoading = true;
  int _selectedSource = -1;
  List<Map<String, dynamic>> _folderFiles = [];
  bool _filesLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.detail(widget.type, widget.tmdbId),
        ApiService.sources(widget.type, widget.tmdbId),
      ]);

      if (mounted) {
        setState(() {
          _detail = results[0];
          _sources = results[1]['sources'] ?? [];
          _loading = false;
          _sourcesLoading = false;
        });

        if (_sources.isNotEmpty) {
          _selectSource(0);
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() { _loading = false; _sourcesLoading = false; });
    }
  }

  Future<void> _selectSource(int idx) async {
    if (idx == _selectedSource) return;
    setState(() { _selectedSource = idx; _filesLoading = true; _folderFiles = []; });

    final source = _sources[idx];
    final url = source['download_url']?.toString() ?? '';

    final match = RegExp(r'folder/([A-Za-z0-9]+)').firstMatch(url);
    if (match == null) {
      setState(() => _filesLoading = false);
      return;
    }

    final linkcode = match.group(1)!;
    final files = await FshareService.listFolder(linkcode);

    if (mounted) {
      final videoFiles = files.where((f) => f['isVideo'] == true).toList();
      videoFiles.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
      setState(() { _folderFiles = videoFiles; _filesLoading = false; });
    }
  }

  Future<void> _playFile(Map<String, dynamic> file) async {
    final linkcode = file['linkcode']?.toString() ?? '';
    if (linkcode.isEmpty) return;

    _showLoadingDialog();

    final directUrl = await FshareService.resolveLink(linkcode);

    if (!mounted) return;
    Navigator.pop(context); // Tắt loading

    if (directUrl != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoUrl: directUrl,
          title: _detail?['title'] ?? _detail?['name'] ?? 'Phim',
          fileName: file['name']?.toString() ?? '',
        ),
      ));
    } else {
      _showErrorSnackBar();
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Color(0xFFE50914)),
        SizedBox(height: 16),
        Text('Đang lấy link stream...', style: TextStyle(color: Colors.white70, fontSize: 14, decoration: TextDecoration.none)),
      ])),
    );
  }

  void _showErrorSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không lấy được link stream. Vui lòng thử lại.'), backgroundColor: Color(0xFFE50914)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D15),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
      );
    }

    final d = _detail ?? {};
    final title = d['title'] ?? d['name'] ?? 'Không có tên';
    final overview = d['overview'] ?? 'Chưa có mô tả.';
    final posterPath = d['poster_path']?.toString() ?? '';
    final rating = (d['vote_average'] ?? 0).toDouble();
    final year = (d['release_date'] ?? d['first_air_date'] ?? '').toString();
    final yearStr = year.length >= 4 ? year.substring(0, 4) : '';
    final genres = (d['genres'] as List?)?.map((g) => g['name'].toString()).toList() ?? [];
    final runtime = d['runtime'] ?? d['episode_run_time']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D15),
      body: Row(
        children: [
          // ── Left: Movie Info ──
          SizedBox(
            width: 400,
            child: Container(
              color: const Color(0xFF111119),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // Back button — dùng Material/InkWell cho D-pad
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        focusColor: const Color(0xFFE50914).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.arrow_back, color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Poster
                  if (posterPath.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: ApiService.posterUrl(posterPath, size: 'w500'),
                        height: 300,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(height: 300, color: const Color(0xFF1C1C30)),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Title
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 8),

                  // Meta row
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (rating > 0) _badge('⭐ ${rating.toStringAsFixed(1)}', const Color(0xFFFFD700)),
                      if (yearStr.isNotEmpty) _badge(yearStr, const Color(0xFF3B82F6)),
                      if (runtime.toString().isNotEmpty && runtime.toString() != '0')
                        _badge('${runtime}m', const Color(0xFF8B5CF6)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Genres
                  if (genres.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: genres.map((g) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                          color: const Color(0xFF1C1C30),
                        ),
                        child: Text(g, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                      )).toList(),
                    ),
                  const SizedBox(height: 16),

                  // Description
                  Text(overview, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6), height: 1.6)),
                ],
              ),
            ),
          ),

          // ── Right: Sources + Files ──
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📂 Danh sách Nguồn Phim', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 16),
                  if (_sourcesLoading)
                    const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))))
                  else if (_sources.isEmpty)
                    Expanded(child: Center(child: Text('Chưa có nguồn Fshare cho phim này', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))))
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sources.length,
                        itemBuilder: (context, index) {
                          final s = _sources[index];
                          final isSelected = index == _selectedSource;
                          final uploader = s['uploader']?.toString() ?? 'unknown';
                          final sheetName = s['sheet_name']?.toString() ?? '';
                          final size = s['size']?.toString() ?? '';
                          Color uploaderColor = uploader.toLowerCase() == 'vietmediaf' ? const Color(0xFFE50914) : (uploader.toLowerCase() == 'thuvienhd' ? const Color(0xFF3B82F6) : const Color(0xFF10B981));

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C30),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFE50914) : Colors.white12,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                DPadFocusBuilder(
                                  autofocus: index == 0 && _selectedSource == -1,
                                  onTap: () => _selectSource(index),
                                  builder: (context, hasFocus) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: hasFocus ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
                                          width: 2.0,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.folder,
                                            color: hasFocus ? const Color(0xFFE50914) : const Color(0xFFFFD700),
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  sheetName,
                                                  style: TextStyle(
                                                    color: hasFocus ? Colors.black : Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: uploaderColor.withValues(alpha: hasFocus ? 0.1 : 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: uploaderColor.withValues(alpha: hasFocus ? 0.4 : 0.3)),
                                                      ),
                                                      child: Text(
                                                        uploader.toUpperCase(),
                                                        style: TextStyle(color: uploaderColor, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                                      ),
                                                    ),
                                                    if (size.isNotEmpty) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        size,
                                                        style: TextStyle(
                                                          color: hasFocus ? Colors.black54 : Colors.white.withValues(alpha: 0.4),
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            color: hasFocus ? Colors.black54 : Colors.white38,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                if (isSelected) ...[
                                  const Divider(color: Colors.white10, height: 1),
                                  if (_filesLoading)
                                    const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator(color: Color(0xFFE50914)),
                                    )
                                  else if (_folderFiles.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                        'Không tìm thấy file video',
                                        style: TextStyle(color: Colors.white38, fontSize: 13),
                                      ),
                                    )
                                  else
                                    Column(
                                      children: _folderFiles.map<Widget>((f) {
                                        return DPadFocusBuilder(
                                          onTap: () => _playFile(f),
                                          builder: (context, fileHasFocus) {
                                            return Container(
                                              decoration: BoxDecoration(
                                                color: fileHasFocus ? Colors.white : Colors.transparent,
                                                border: const Border(top: BorderSide(color: Colors.white10, width: 0.5)),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.play_circle_fill, color: Color(0xFFE50914), size: 28),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          f['name'],
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w600,
                                                            color: fileHasFocus ? Colors.black : Colors.white,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        if (f['sizeFormatted'] != null) ...[
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            f['sizeFormatted'],
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: fileHasFocus ? Colors.black54 : Colors.white.withValues(alpha: 0.4),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFE50914),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: fileHasFocus ? Colors.black : Colors.transparent,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.play_arrow, size: 14, color: Colors.white),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          'Xem',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.w700,
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
  );
}

class DPadFocusBuilder extends StatefulWidget {
  final bool autofocus;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hasFocus) builder;

  const DPadFocusBuilder({
    super.key,
    required this.onTap,
    required this.builder,
    this.autofocus = false,
  });

  @override
  State<DPadFocusBuilder> createState() => _DPadFocusBuilderState();
}

class _DPadFocusBuilderState extends State<DPadFocusBuilder> {
  late final FocusNode _node;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _node = FocusNode();
    _node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _hasFocus = _node.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      focusNode: _node,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: widget.builder(context, _hasFocus),
    );
  }
}
