import 'package:flutter/material.dart';

/// Virtual Keyboard Dialog cho Android TV (dùng remote D-pad)
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _append(String char) {
    setState(() {
      _ctrl.text = _ctrl.text + char;
    });
  }

  void _backspace() {
    if (_ctrl.text.isNotEmpty) {
      setState(() {
        _ctrl.text = _ctrl.text.substring(0, _ctrl.text.length - 1);
      });
    }
  }

  void _clear() {
    setState(() {
      _ctrl.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF15151F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        height: 380,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Left Side: Text display + main action buttons
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔍 Tìm kiếm phim',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
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
                  const Spacer(),
                  // Action buttons: Dấu cách, Xóa, Xóa hết
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton('Dấu cách', Icons.space_bar, () => _append(' ')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _actionButton('Xóa', Icons.backspace, _backspace),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton('Xóa hết', Icons.clear_all, _clear),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Cancel / Search Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Hủy', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, _ctrl.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Text('Tìm', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 14)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            const VerticalDivider(color: Colors.white12, width: 1),
            const SizedBox(width: 24),
            // Right Side: Grid of A-Z, 0-9
            Expanded(
              flex: 5,
              child: GridView.builder(
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
                  return Material(
                    color: const Color(0xFF1C1C30),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => _append(keyStr),
                      autofocus: idx == 0, // Tự động bắt nét vào phím chữ A đầu tiên
                      focusColor: const Color(0xFFE50914).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        child: Text(
                          keyStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF1C1C30),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        focusColor: const Color(0xFFE50914).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
