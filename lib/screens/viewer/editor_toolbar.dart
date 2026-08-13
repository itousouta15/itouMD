import 'package:flutter/material.dart';

import '../../theme.dart';

/// A horizontally-scrolling row of Markdown formatting shortcuts, docked
/// directly above the keyboard (it's the last child in the edit body's
/// [Column], which the [Scaffold] pushes up above the software keyboard
/// automatically) so common syntax doesn't have to be typed by hand.
class EditorToolbar extends StatelessWidget {
  final ItouColors c;
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onStrikethrough;
  final VoidCallback onInlineCode;
  final VoidCallback onCodeBlock;
  final VoidCallback onQuote;
  final VoidCallback onBulletList;
  final VoidCallback onNumberedList;
  final VoidCallback onTaskList;
  final VoidCallback onLink;
  final VoidCallback onAi;

  const EditorToolbar({
    super.key,
    required this.c,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onStrikethrough,
    required this.onInlineCode,
    required this.onCodeBlock,
    required this.onQuote,
    required this.onBulletList,
    required this.onNumberedList,
    required this.onTaskList,
    required this.onLink,
    required this.onAi,
  });

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      color: c.text,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      // Toolbar taps must not steal keyboard focus from the TextField —
      // handled by the callbacks themselves (they re-request focus after
      // editing the controller), not by anything here.
      onPressed: onTap,
    );
  }

  /// The AI assistant button — visually set apart from the plain format
  /// buttons so it reads as a distinct feature, not another toggle.
  Widget _aiBtn() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1, height: 24, color: c.border),
        const SizedBox(width: 6),
        Tooltip(
          message: 'AI 助理（潤飾／翻譯／改寫）',
          child: Material(
            color: c.blue,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onAi,
              borderRadius: BorderRadius.circular(8),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.auto_awesome, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.title, '標題', onHeading),
              _btn(Icons.format_bold, '粗體', onBold),
              _btn(Icons.format_italic, '斜體', onItalic),
              _btn(Icons.strikethrough_s, '刪除線', onStrikethrough),
              _btn(Icons.code, '行內程式碼', onInlineCode),
              _btn(Icons.data_object, '程式碼區塊', onCodeBlock),
              _btn(Icons.format_quote, '引用', onQuote),
              _btn(Icons.format_list_bulleted, '項目清單', onBulletList),
              _btn(Icons.format_list_numbered, '編號清單', onNumberedList),
              _btn(Icons.check_box_outlined, '待辦清單', onTaskList),
              _btn(Icons.link, '連結', onLink),
              _aiBtn(),
            ],
          ),
        ),
      ),
    );
  }
}
