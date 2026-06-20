import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

/// Movie Card — dùng InkWell (hỗ trợ D-pad remote bấm OK = onTap)
class MovieCard extends StatefulWidget {
  final Map<String, dynamic> movie;
  final String type;
  final bool? hasFshare;
  final VoidCallback? onTap;

  const MovieCard({
    super.key,
    required this.movie,
    this.type = 'movie',
    this.hasFshare,
    this.onTap,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.movie;
    final title = m['title'] ?? m['name'] ?? 'Untitled';
    final posterPath = m['poster_path']?.toString() ?? '';
    final posterUrl = ApiService.posterUrl(posterPath);
    final rating = (m['vote_average'] ?? 0).toDouble();
    final ratingStr = rating > 0 ? rating.toStringAsFixed(1) : '';
    final year = (m['release_date'] ?? m['first_air_date'] ?? '').toString();
    final yearStr = year.length >= 4 ? year.substring(0, 4) : '';

    // Material + InkWell → D-pad OK = onTap, focus highlight tự động
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        focusColor: const Color(0xFFE50914).withValues(alpha: 0.15),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        onFocusChange: (f) => setState(() => _focused = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: _focused ? Matrix4.diagonal3Values(1.05, 1.05, 1.0) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? const Color(0xFFE50914) : Colors.transparent,
              width: _focused ? 3.0 : 1.0,
            ),
            boxShadow: _focused
                ? [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.5), blurRadius: 16)]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image
                      posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFF1C1C30),
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE50914))),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF1C1C30),
                                child: const Center(child: Text('🎬', style: TextStyle(fontSize: 32))),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF1C1C30),
                              child: const Center(child: Text('🎬', style: TextStyle(fontSize: 32))),
                            ),

                      // Badge Fshare
                      if (widget.hasFshare == true)
                        Positioned(
                          top: 8, left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF2ECC71), Color(0xFF27AE60)]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Fshare', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),

                      // Favorite button
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(15)),
                          child: const Icon(Icons.favorite_border, color: Colors.white70, size: 16),
                        ),
                      ),

                      // Rating
                      if (ratingStr.isNotEmpty)
                        Positioned(
                          bottom: 8, left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.star, color: Color(0xFFFFD700), size: 12),
                              const SizedBox(width: 3),
                              Text(ratingStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Title + Year
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (yearStr.isNotEmpty)
                Text(yearStr, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Xem Tất Cả" card
class SeeAllCard extends StatelessWidget {
  final VoidCallback? onTap;
  const SeeAllCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        focusColor: const Color(0xFFE50914).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFFF6B35)]),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 12),
                    const Text('XEM TẤT CẢ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 13),
            const SizedBox(height: 11),
          ],
        ),
      ),
    );
  }
}
