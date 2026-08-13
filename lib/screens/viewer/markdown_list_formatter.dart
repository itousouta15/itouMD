import 'package:flutter/services.dart';

import '../../services/markdown_editor_actions.dart';

/// Turns "press Enter on a list item" into "continue the list" instead of a
/// bare newline — the single biggest bit of editor friction on mobile,
/// where retyping `- ` for every line is tedious with no physical keyboard.
class MarkdownListContinuationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Don't interfere mid-IME-composition (CJK input etc.).
    if (newValue.composing != TextRange.empty) return newValue;
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    if (!newValue.selection.isCollapsed) return newValue;

    final insertionIndex = newValue.selection.baseOffset - 1;
    if (insertionIndex < 0 || insertionIndex >= newValue.text.length) {
      return newValue;
    }
    if (newValue.text[insertionIndex] != '\n') return newValue;

    final result = computeEnterListContinuation(newValue.text, insertionIndex);
    if (result == null) return newValue;

    return TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }
}
