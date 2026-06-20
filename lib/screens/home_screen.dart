import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/fshare_service.dart';
import '../services/update_service.dart';
import '../widgets/movie_card.dart';
import '../widgets/virtual_keyboard_dialog.dart';
import 'movie_detail_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentPage = 'home';
  List<dynamic> _trendingMovies = [];
  List<dynamic> _trendingTV = [];
  List<dynamic> _pageResults = [];
  Map<String, dynamic> _cachedFshare = {};
  bool _loading = true;
  bool _pageLoading = false;
  String _pageTitle = '';
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadHome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    setState(() { _loading = true; _currentPage = 'home'; });
    try {
      final results = await Future.wait([
        ApiService.trending('movie'),
        ApiService.trending('tv'),
      ]);

      final movies = (results[0]['results'] as List?) ?? [];
      final tvShows = (results[1]['results'] as List?) ?? [];

      final movieIds = movies.map<int>((m) => m['id'] as int).toList();
      final tvIds = tvShows.map<int>((t) => t['id'] as int).toList();
      Map<String, dynamic> cached = {};
      try { cached = await ApiService.batchCheck(movieIds, tvIds); } catch (_) {}

      if (mounted) {
        setState(() {
          _trendingMovies = movies;
          _trendingTV = tvShows;
          _cachedFshare = cached;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading home: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPage(String page, String title, {int pageNum = 1}) async {
    setState(() { _pageLoading = true; _currentPage = page; _pageTitle = title; });
    try {
      Map<String, dynamic> data;
      switch (page) {
        case 'trending-movie': data = await ApiService.trending('movie', page: pageNum); break;
        case 'trending-tv': data = await ApiService.trending('tv', page: pageNum); break;
        case 'now-playing': data = await ApiService.nowPlaying(page: pageNum); break;
        case 'top-movie': data = await ApiService.topRated('movie', page: pageNum); break;
        case 'top-tv': data = await ApiService.topRated('tv', page: pageNum); break;
        default: data = await ApiService.trending('movie', page: pageNum);
      }

      final results = (data['results'] as List?) ?? [];
      final mediaType = page.contains('tv') ? 'tv' : 'movie';
      final ids = results.map<int>((m) => m['id'] as int).toList();
      Map<String, dynamic> cached = {};
      try {
        cached = await ApiService.batchCheck(
          mediaType == 'movie' ? ids : [], mediaType == 'tv' ? ids : [],
        );
      } catch (_) {}

      if (mounted) {
        setState(() { _pageResults = results; _cachedFshare = cached; _pageLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _pageLoading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.length < 2) return;
    setState(() { _pageLoading = true; _currentPage = 'search'; _pageTitle = 'Kết quả: "$query"'; });
    try {
      // 1. Tách ngôn ngữ/quốc gia khỏi truy vấn
      final langMaps = [
        {'keys': ['hàn quốc', 'phim hàn'], 'code': 'ko'},
        {'keys': ['trung quốc', 'phim trung'], 'code': 'zh'},
        {'keys': ['nhật bản', 'phim nhật'], 'code': 'ja'},
        {'keys': ['việt nam', 'phim việt'], 'code': 'vi'},
        {'keys': ['thái lan', 'phim thái'], 'code': 'th'},
        {'keys': ['mỹ', 'âu mỹ', 'phim mỹ'], 'code': 'en'},
        {'keys': ['ấn độ', 'phim ấn'], 'code': 'hi'},
      ];

      String? origLang;
      String cleanQuery = query.toLowerCase();

      for (final item in langMaps) {
        final keys = item['keys'] as List<String>;
        for (final key in keys) {
          if (cleanQuery.contains(key)) {
            origLang = item['code'] as String;
            cleanQuery = cleanQuery.replaceAll(key, '').trim();
            break;
          }
        }
        if (origLang != null) break;
      }

      // 2. Tách năm
      String? year;
      final yearRegex = RegExp(r'\s?\(?(19\d{2}|20\d{2})\)?$');
      final match = yearRegex.firstMatch(cleanQuery);
      if (match != null) {
        year = match.group(1);
        cleanQuery = cleanQuery.replaceAll(match.group(0)!, '').trim();
      }

      final isAdvanced = origLang != null || year != null;
      final isPureDiscover = isAdvanced && cleanQuery.length < 2;

      Map<String, dynamic> moviesData;
      Map<String, dynamic> tvShowsData;

      if (isPureDiscover) {
        moviesData = await ApiService.discover('movie', year: year, origLang: origLang);
        tvShowsData = await ApiService.discover('tv', year: year, origLang: origLang);
      } else {
        final queryToSearch = cleanQuery.isNotEmpty ? cleanQuery : query;
        moviesData = await ApiService.searchMovies(queryToSearch, year: year);
        tvShowsData = await ApiService.searchTV(queryToSearch, year: year);
      }

      final movies = (moviesData['results'] as List?) ?? [];
      final tvShows = (tvShowsData['results'] as List?) ?? [];
      final all = [
        ...movies.map((m) { m['_type'] = 'movie'; return m; }),
        ...tvShows.map((t) { t['_type'] = 'tv'; return t; })
      ];

      final movieIds = movies.map<int>((m) => m['id'] as int).toList();
      final tvIds = tvShows.map<int>((t) => t['id'] as int).toList();
      Map<String, dynamic> cached = {};
      try { cached = await ApiService.batchCheck(movieIds, tvIds); } catch (_) {}

      // 3. Lọc chỉ giữ lại phim có link Fshare (đồng bộ onlyWithLinks trên PC)
      final filteredAll = all.where((item) {
        final id = item['id'].toString();
        return cached[id]?['cached'] == true;
      }).toList();

      if (mounted) {
        setState(() {
          // Phương án dự phòng: nếu lọc xong không còn phim nào thì hiển thị toàn bộ kết quả tìm kiếm được
          _pageResults = filteredAll.isNotEmpty ? filteredAll : all;
          _cachedFshare = cached;
          _pageLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _pageLoading = false);
    }
  }

  void _showSearch() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => const VirtualKeyboardDialog(initialText: ''),
    );
    if (result == null) return;
    if (result is Map<String, dynamic>) {
      final type = result['_type'] ?? result['media_type'] ?? 'movie';
      _openMovie(result, type);
    } else if (result is String && result.trim().isNotEmpty) {
      _search(result.trim());
    }
  }

  void _openMovie(Map<String, dynamic> movie, String type) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MovieDetailScreen(tmdbId: movie['id'] as int, type: type),
    ));
  }

  void _logout() async {
    await FshareService.logout();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentPage != 'home') {
          _loadHome();
          return;
        }
        _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D15),
        body: Row(
          children: [
            _buildSidebar(),
            Expanded(
              child: _currentPage == 'home' ? _buildHomeContent() : _buildPageContent(),
            ),
          ],
        ),
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15151F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thoát ứng dụng?', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        content: const Text('Bạn có muốn thoát Kh.le TV?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Không', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            child: const Text('Thoát', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  SIDEBAR — Material/InkWell cho D-pad
  // ══════════════════════════════════════
  Widget _buildSidebar() {
    return Container(
      width: 180,
      color: const Color(0xFF111119),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFFF6B35)]),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              RichText(text: const TextSpan(children: [
                TextSpan(text: 'Kh.le', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                TextSpan(text: 'TV', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFE50914))),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // Search — InkWell cho D-pad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showSearch,
                focusColor: const Color(0xFFE50914).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    const SizedBox(width: 8),
                    Text('Tìm phim...', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          _navLabel('KHÁM PHÁ'),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _navItem(Icons.home_filled, 'Trang chủ', 'home', _loadHome),
                _navItem(Icons.local_fire_department, 'Phim Hot', 'trending-movie', () => _loadPage('trending-movie', '🔥 Phim Hot')),
                _navItem(Icons.tv, 'TV Hot', 'trending-tv', () => _loadPage('trending-tv', '📺 TV Hot')),
                _navItem(Icons.explore, 'Khám phá', 'discovery', () => _loadPage('trending-movie', '🧭 Khám phá')),
                _navItem(Icons.movie_creation, 'Đang chiếu', 'now-playing', () => _loadPage('now-playing', '🎬 Đang chiếu')),
                _navItem(Icons.star, 'Top Phim', 'top-movie', () => _loadPage('top-movie', '⭐ Top Phim')),
                _navItem(Icons.star_border, 'Top TV', 'top-tv', () => _loadPage('top-tv', '🌟 Top TV')),
                const Divider(color: Colors.white10, height: 24, indent: 16, endIndent: 16),
                _navItem(Icons.settings, 'Cài đặt', 'settings', () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }),
                _navItem(Icons.logout, 'Đăng xuất', 'logout', _logout),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.25), letterSpacing: 1.2)),
  );

  /// Nav item — Material/InkWell tự động hỗ trợ D-pad
  Widget _navItem(IconData icon, String label, String page, VoidCallback onTap) {
    final active = _currentPage == page;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? const Color(0xFFE50914).withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          focusColor: const Color(0xFFE50914).withValues(alpha: 0.3),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 18, color: active ? const Color(0xFFE50914) : Colors.white54),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? Colors.white : Colors.white70)),
            ]),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  HOME CONTENT
  // ══════════════════════════════════════
  Widget _buildHomeContent() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)));

    return SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('🔥 Phim Hot'),
          const SizedBox(height: 16),
          _buildMovieRow(_trendingMovies.take(9).toList(), 'movie', 'trending-movie'),
          const SizedBox(height: 32),
          _buildSectionHeader('📺 TV Shows Hot'),
          const SizedBox(height: 16),
          _buildMovieRow(_trendingTV.take(9).toList(), 'tv', 'trending-tv'),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white));
  }

  Widget _buildMovieRow(List<dynamic> movies, String type, String seeAllPage) {
    final itemCount = movies.length + 1;
    return SizedBox(
      height: 280,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (_, i) {
          if (i == movies.length) {
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(width: 155, child: SeeAllCard(onTap: () => _loadPage(seeAllPage, seeAllPage))),
            );
          }
          final movie = movies[i];
          final id = movie['id'].toString();
          final hasFshare = _cachedFshare[id]?['cached'] == true;
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: SizedBox(
              width: 155,
              child: MovieCard(
                movie: movie,
                type: type,
                hasFshare: hasFshare,
                onTap: () => _openMovie(movie, type),
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════
  //  PAGE CONTENT (Grid)
  // ══════════════════════════════════════
  Widget _buildPageContent() {
    if (_pageLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)));

    if (_pageResults.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔍', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Không có dữ liệu', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
      ]));
    }

    final mediaType = _currentPage.contains('tv') ? 'tv' : 'movie';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Text(_pageTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180, childAspectRatio: 0.55, crossAxisSpacing: 14, mainAxisSpacing: 14,
            ),
            itemCount: _pageResults.length,
            itemBuilder: (_, i) {
              final movie = _pageResults[i];
              final id = movie['id'].toString();
              final hasFshare = _cachedFshare[id]?['cached'] == true;
              final type = movie['_type']?.toString() ?? mediaType;
              return MovieCard(
                movie: movie,
                type: type,
                hasFshare: hasFshare,
                onTap: () => _openMovie(movie, type),
              );
            },
          ),
        ),
      ],
    );
  }
}
