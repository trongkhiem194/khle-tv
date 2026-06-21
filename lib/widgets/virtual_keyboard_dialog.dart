import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

/// Virtual Keyboard Dialog cho Android TV (dùng remote D-pad)
/// Hỗ trợ tìm kiếm giọng nói (Speech-to-Text) và gợi ý kết quả thời gian thực
class VirtualKeyboardDialog extends StatefulWidget {
  final String initialText;
  const VirtualKeyboardDialog({super.key, this.initialText = ''});
  @override
  State<VirtualKeyboardDialog> createState() => _VirtualKeyboardDialogState();
}

class _VirtualKeyboardDialogState extends State<VirtualKeyboardDialog> {
  late TextEditingController _ctrl;
  final List<String> _keys = [
    'A', 'B', 'C', 'D', 'E', 'F',
    'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R',
    'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9',
  ];

  // Giọng nói
  late stt.SpeechToText _speech;
  bool _speechEnabled = false;
  bool _listening = false;

  // Gợi ý tìm kiếm
  Timer? _debounce;
  List<dynamic> _suggestions = [];
  bool _searchingSuggestions = false;

  // D-pad Focus Nodes
  final FocusNode _voiceFocusNode = FocusNode();
  final FocusNode _spaceFocusNode = FocusNode();
  final FocusNode _backspaceFocusNode = FocusNode();
  final FocusNode _clearFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final List<FocusNode> _keyFocusNodes = List.generate(36, (_) => FocusNode());
  List<FocusNode> _suggestionFocusNodes = [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _speech = stt.SpeechToText();
    _initSpeech();
    _initFocusNodes();
    if (widget.initialText.isNotEmpty) {
      _onTextChanged(widget.initialText);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    _voiceFocusNode.dispose();
    _spaceFocusNode.dispose();
    _backspaceFocusNode.dispose();
    _clearFocusNode.dispose();
    _cancelFocusNode.dispose();
    _searchFocusNode.dispose();
    for (final node in _keyFocusNodes) {
      node.dispose();
    }
    for (final node in _suggestionFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _initFocusNodes() {
    // 1. Voice Focus Node
    _voiceFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_suggestionFocusNodes.isNotEmpty) {
          _suggestionFocusNodes[0].requestFocus();
          return KeyEventResult.handled;
        } else {
          _cancelFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _keyFocusNodes[0].requestFocus(); // Focus key 'A'
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // 2. Keyboard keys Focus Nodes (36 keys, 6x6 grid)
    for (int i = 0; i < 36; i++) {
      final idx = i;
      _keyFocusNodes[idx].onKeyEvent = (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final row = idx ~/ 6;
        final col = idx % 6;

        if (key == LogicalKeyboardKey.arrowUp) {
          if (row > 0) {
            _keyFocusNodes[idx - 6].requestFocus();
            return KeyEventResult.handled;
          } else {
            _voiceFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (row < 5) {
            _keyFocusNodes[idx + 6].requestFocus();
            return KeyEventResult.handled;
          } else {
            // Row 5 -> move to action buttons below
            if (col < 3) {
              _spaceFocusNode.requestFocus();
            } else if (col == 3 || col == 4) {
              _backspaceFocusNode.requestFocus();
            } else {
              _clearFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (col > 0) {
            _keyFocusNodes[idx - 1].requestFocus();
            return KeyEventResult.handled;
          } else {
            // Col 0 -> go to suggestions on the left
            if (_suggestionFocusNodes.isNotEmpty) {
              final targetIdx = row.clamp(0, _suggestionFocusNodes.length - 1);
              _suggestionFocusNodes[targetIdx].requestFocus();
              return KeyEventResult.handled;
            } else {
              _voiceFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
          }
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          if (col < 5) {
            _keyFocusNodes[idx + 1].requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }

    // 3. Space Focus Node
    _spaceFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _keyFocusNodes[30].requestFocus(); // Key '4'
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _cancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_suggestionFocusNodes.isNotEmpty) {
          _suggestionFocusNodes.last.requestFocus();
        } else {
          _voiceFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _backspaceFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // 4. Backspace Focus Node
    _backspaceFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _keyFocusNodes[33].requestFocus(); // Key '7'
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _spaceFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _clearFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // 5. Clear Focus Node
    _clearFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _keyFocusNodes[35].requestFocus(); // Key '9'
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _backspaceFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // 6. Cancel Focus Node
    _cancelFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _spaceFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_suggestionFocusNodes.isNotEmpty) {
          _suggestionFocusNodes.last.requestFocus();
        } else {
          _voiceFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // 7. Search Focus Node
    _searchFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _clearFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _cancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  void _updateSuggestions(List<dynamic> newList) {
    for (final node in _suggestionFocusNodes) {
      node.dispose();
    }
    _suggestionFocusNodes = List.generate(newList.length, (idx) {
      final node = FocusNode();
      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowUp) {
          if (idx > 0) {
            _suggestionFocusNodes[idx - 1].requestFocus();
          } else {
            _voiceFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (idx < _suggestionFocusNodes.length - 1) {
            _suggestionFocusNodes[idx + 1].requestFocus();
          } else {
            _cancelFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          final targetKeyIdx = (idx * 6).clamp(0, 35);
          _keyFocusNodes[targetKeyIdx].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
      return node;
    });
    _suggestions = newList;
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (val) {
          debugPrint('[Speech] onStatus: $val');
          if (val == 'done' || val == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (val) {
          debugPrint('[Speech] onError: $val');
          setState(() => _listening = false);
        },
      );
      if (mounted) {
        setState(() {
          _speechEnabled = available;
        });
      }
    } catch (e) {
      debugPrint('[Speech] Init error: $e');
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      await _initSpeech();
    }
    if (_speechEnabled) {
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (val) {
          if (val.recognizedWords.isNotEmpty) {
            setState(() {
              _ctrl.text = val.recognizedWords;
            });
            _onTextChanged(val.recognizedWords);
          }
          if (val.finalResult) {
            _stopListening();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: 'vi_VN',
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 2),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy dịch vụ giọng nói hoặc quyền bị từ chối')),
        );
      }
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  void _onTextChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _updateSuggestions([]);
        _searchingSuggestions = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searchingSuggestions = true);
      try {
        final query = text.trim();
        final results = await Future.wait([
          ApiService.searchMovies(query),
          ApiService.searchTV(query),
        ]);

        final movies = (results[0]['results'] as List?) ?? [];
        final tv = (results[1]['results'] as List?) ?? [];

        final combined = [
          ...movies.take(3).map((m) { m['_type'] = 'movie'; return m; }),
          ...tv.take(3).map((t) { t['_type'] = 'tv'; return t; }),
        ];

        final suggestionsList = combined.take(4).toList();

        if (mounted && _ctrl.text.trim() == query) {
          setState(() {
            _updateSuggestions(suggestionsList);
            _searchingSuggestions = false;
          });
        }
      } catch (e) {
        debugPrint('[Suggestions] Error: $e');
        if (mounted) {
          setState(() => _searchingSuggestions = false);
        }
      }
    });
  }

  void _append(String char) {
    setState(() {
      _ctrl.text = _ctrl.text + char;
    });
    _onTextChanged(_ctrl.text);
  }

  void _backspace() {
    if (_ctrl.text.isNotEmpty) {
      setState(() {
        _ctrl.text = _ctrl.text.substring(0, _ctrl.text.length - 1);
      });
      _onTextChanged(_ctrl.text);
    }
  }

  void _clear() {
    setState(() {
      _ctrl.text = '';
    });
    _onTextChanged(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF15151F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 850,
        height: 480,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Left Side: Text display + Voice Button + Suggestions
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '🔍 Tìm kiếm phim',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const Spacer(),
                      _voiceSearchButton(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    readOnly: true, // Không hiện bàn phím hệ thống
                    focusNode: FocusNode(canRequestFocus: false),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Nhập tên phim...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: const Color(0xFF1C1C30),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const Text('Gợi ý phim:', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _searchingSuggestions
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                      : (_suggestions.isEmpty
                          ? Center(
                              child: Text(
                                _ctrl.text.isEmpty ? 'Nhập tên phim để xem gợi ý...' : 'Không tìm thấy gợi ý nào',
                                style: const TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: _suggestions.asMap().entries.map<Widget>((e) => _suggestionItem(e.value, _suggestionFocusNodes[e.key])).toList(),
                            )),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            const VerticalDivider(color: Colors.white12, width: 1),
            const SizedBox(width: 24),
            // Right Side: Grid of A-Z, 0-9 + Actions
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _keys.length,
                    itemBuilder: (ctx, idx) {
                      final keyStr = _keys[idx];
                      return DPadFocusBuilder(
                        focusNode: _keyFocusNodes[idx],
                        autofocus: idx == 0,
                        onTap: () => _append(keyStr),
                        builder: (context, hasFocus) {
                          return Container(
                            decoration: BoxDecoration(
                              color: hasFocus ? Colors.white : const Color(0xFF1C1C30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              keyStr,
                              style: TextStyle(
                                color: hasFocus ? Colors.black : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _actionButton('Dấu cách', Icons.space_bar, _spaceFocusNode, () => _append(' ')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: _actionButton('Xóa', Icons.backspace, _backspaceFocusNode, _backspace),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: _actionButton('Xóa hết', Icons.clear_all, _clearFocusNode, _clear),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Cancel / Search Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      DPadFocusBuilder(
                        focusNode: _cancelFocusNode,
                        onTap: () => Navigator.pop(context),
                        builder: (context, hasFocus) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: hasFocus ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              'Hủy',
                              style: TextStyle(
                                color: hasFocus ? Colors.black : Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      DPadFocusBuilder(
                        focusNode: _searchFocusNode,
                        onTap: () => Navigator.pop(context, _ctrl.text),
                        builder: (context, hasFocus) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: hasFocus ? Colors.white : const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              'Tìm',
                              style: TextStyle(
                                color: hasFocus ? const Color(0xFFE50914) : Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceSearchButton() {
    return DPadFocusBuilder(
      focusNode: _voiceFocusNode,
      onTap: _listening ? _stopListening : _startListening,
      builder: (context, hasFocus) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _listening
                ? const Color(0xFFE50914)
                : (hasFocus ? Colors.white : const Color(0xFF1C1C30)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _listening ? Icons.mic : Icons.mic_none,
                color: _listening
                    ? Colors.white
                    : (hasFocus ? const Color(0xFFE50914) : Colors.white70),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _listening ? 'Đang nghe...' : 'Giọng nói',
                style: TextStyle(
                  color: _listening
                      ? Colors.white
                      : (hasFocus ? Colors.black : Colors.white70),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton(String label, IconData icon, FocusNode node, VoidCallback onTap) {
    return DPadFocusBuilder(
      focusNode: node,
      onTap: onTap,
      builder: (context, hasFocus) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: hasFocus ? Colors.white : const Color(0xFF1C1C30),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: hasFocus ? Colors.black : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: hasFocus ? Colors.black : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _suggestionItem(Map<String, dynamic> movie, FocusNode node) {
    final title = movie['title'] ?? movie['name'] ?? 'Không có tên';
    final releaseDate = movie['release_date'] ?? movie['first_air_date'] ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
    final posterPath = movie['poster_path']?.toString() ?? '';

    return DPadFocusBuilder(
      focusNode: node,
      onTap: () {
        Navigator.pop(context, movie); // Trả về Map thông tin phim trực tiếp
      },
      builder: (context, hasFocus) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: hasFocus ? Colors.white : const Color(0xFF1C1C30),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasFocus ? const Color(0xFFE50914) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              if (posterPath.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: ApiService.posterUrl(posterPath, size: 'w92'),
                    width: 32,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(width: 32, height: 48, color: Colors.white12),
                  ),
                )
              else
                Container(
                  width: 32,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.movie, size: 16, color: Colors.white24),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: hasFocus ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (year.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        year,
                        style: TextStyle(
                          color: hasFocus ? Colors.black54 : Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DPadFocusBuilder extends StatefulWidget {
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hasFocus) builder;

  const DPadFocusBuilder({
    super.key,
    required this.onTap,
    required this.builder,
    this.focusNode,
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
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _node.dispose();
    }
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
