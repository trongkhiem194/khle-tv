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
                  const Text('📂 Chọn Nguồn Fshare', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 16),

                  // Source list — dùng Material/InkWell cho D-pad
                  if (_sourcesLoading)
                    const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                  else if (_sources.isEmpty)
                    Center(child: Text('Chưa có nguồn Fshare cho phim này', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))))
                  else
                    SizedBox(
                      height: 55,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _sources.length,
                        itemBuilder: (_, i) {
                          final s = _sources[i];
                          final active = i == _selectedSource;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: active ? const Color(0xFFE50914) : const Color(0xFF1C1C30),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () => _selectSource(i),
                                borderRadius: BorderRadius.circular(10),
                                focusColor: const Color(0xFFE50914).withValues(alpha: 0.4),
                                hoverColor: const Color(0xFFE50914).withValues(alpha: 0.2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: active ? const Color(0xFFE50914) : Colors.white12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(s['sheet_name'] ?? 'Nguồn ${i + 1}',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.white70)),
                                      Text(s['size'] ?? '', style: TextStyle(fontSize: 10, color: active ? Colors.white70 : Colors.white38)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 20),

                  // File list — dùng Material/InkWell cho D-pad
                  if (_selectedSource >= 0) ...[
                    Row(
                      children: [
                        Text('🎬 Danh sách file', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '(Mẹo: Nên ưu tiên chọn các nguồn nhẹ 1.5GB - 4GB để xem mượt nhất)',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4), fontStyle: FontStyle.italic),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filesLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFE50914))))
                    else if (_folderFiles.isEmpty)
                      Center(child: Text('Không tìm thấy file video', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))))
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: _folderFiles.length,
                          itemBuilder: (_, i) {
                            final f = _folderFiles[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: const Color(0xFF1C1C30),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () => _playFile(f),
                                  borderRadius: BorderRadius.circular(10),
                                  focusColor: const Color(0xFFE50914).withValues(alpha: 0.3),
                                  hoverColor: Colors.white.withValues(alpha: 0.05),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.play_circle_fill, color: Color(0xFFE50914), size: 36),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(f['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                                              const SizedBox(height: 2),
                                              Text(f['sizeFormatted'] ?? '', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE50914),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.play_arrow, size: 18, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text('Xem', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ] else
                    Expanded(
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.touch_app, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text('Chọn một nguồn ở trên để xem danh sách file', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                        ]),
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
