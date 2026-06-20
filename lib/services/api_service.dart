import 'dart:convert';
import 'package:http/http.dart' as http;

/// API Service để gọi VietmediaF Store API
/// Nguồn metadata phim từ TMDB + link Fshare
class ApiService {
  static const String baseUrl = 'https://vietmediaf.store';
  static const String imgBase = 'https://image.tmdb.org/t/p';
  static const String lang = 'vi-VN';
  static const Map<String, String> _headers = {
    'User-Agent': 'VietMediaDesktop/1.0',
    'Accept': 'application/json',
  };

  // ── Poster/Backdrop URL helpers ──
  static String posterUrl(String? path, {String size = 'w342'}) {
    if (path == null || path.isEmpty) return '';
    return '$imgBase/$size$path';
  }

  static String backdropUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$imgBase/w1280$path';
  }

  // ── Trending (Phim Hot / TV Hot) ──
  static Future<Map<String, dynamic>> trending(String type, {int page = 1}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/tmdb/trending/$type?page=$page&lang=$lang'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Search ──
  static Future<Map<String, dynamic>> searchMovies(String query, {int page = 1, String? year}) async {
    String url = '$baseUrl/api/tmdb/search/movie?q=${Uri.encodeComponent(query)}&page=$page&lang=$lang';
    if (year != null) url += '&year=$year';
    final res = await http.get(Uri.parse(url), headers: _headers);
    return json.decode(res.body);
  }

  static Future<Map<String, dynamic>> searchTV(String query, {int page = 1, String? year}) async {
    String url = '$baseUrl/api/tmdb/search/tv?q=${Uri.encodeComponent(query)}&page=$page&lang=$lang';
    if (year != null) url += '&year=$year';
    final res = await http.get(Uri.parse(url), headers: _headers);
    return json.decode(res.body);
  }

  // ── Detail ──
  static Future<Map<String, dynamic>> detail(String type, int id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/tmdb/$type/$id?lang=$lang'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Sources (Fshare links) ──
  static Future<Map<String, dynamic>> sources(String type, int id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/$type/$id'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Genres ──
  static Future<Map<String, dynamic>> genres(String type) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/tmdb/genres/$type?lang=$lang'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Discover ──
  static Future<Map<String, dynamic>> discover(String type, {String? genreId, int page = 1}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/tmdb/discover/$type?genre=${genreId ?? ''}&page=$page&lang=$lang'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Now Playing ──
  static Future<Map<String, dynamic>> nowPlaying({int page = 1}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/tmdb/now-playing?page=$page&lang=$lang'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Top Rated ──
  static Future<Map<String, dynamic>> topRated(String type, {int page = 1}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/tmdb/top-rated/$type?page=$page&lang=$lang'),
      headers: _headers,
    );
    return json.decode(res.body);
  }

  // ── Batch Check (có Fshare hay không) ──
  static Future<Map<String, dynamic>> batchCheck(List<int> movieIds, List<int> tvIds) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/batch/mixed'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: json.encode({'movies': movieIds, 'tv_shows': tvIds}),
    );
    final data = json.decode(res.body);
    return data['results'] ?? {};
  }
}
