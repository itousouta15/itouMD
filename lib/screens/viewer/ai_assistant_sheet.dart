import 'package:flutter/material.dart';

import '../../services/llm_client.dart';
import '../../services/llm_prefs.dart';
import '../../services/markdown_diff.dart';
import '../../theme.dart';
import '../../widgets/diff_view.dart';

/// Instruction presets for the AI assistant: label + prompt template where
/// `{text}` is replaced by the selected text (or the whole document).
const _aiInstructions = <(String, String)>[
  ('潤飾', '請潤飾以下內容，讓它更通順自然，保留 Markdown 格式：\n\n{text}'),
  ('翻譯成繁體中文', '請將以下內容翻譯成繁體中文，保留 Markdown 格式：\n\n{text}'),
  ('翻譯成英文', '請將以下內容翻譯成英文，保留 Markdown 格式：\n\n{text}'),
  ('縮寫', '請將以下內容縮短並保留重點，保留 Markdown 格式：\n\n{text}'),
  ('改寫', '請以不同寫法改寫以下內容、保留原意，保留 Markdown 格式：\n\n{text}'),
  ('生成摘要', '請為以下內容生成簡短摘要，保留 Markdown 格式：\n\n{text}'),
  ('擴寫內容', '請將以下內容擴寫得更詳細完整，補足說明與例子，保留 Markdown 格式：\n\n{text}'),
  ('整理成表格', '請將以下內容整理成 Markdown 表格，設計清楚的欄位與表頭：\n\n{text}'),
  ('整理成清單', '請將以下內容整理成條列式清單（項目符號或編號），保留重點：\n\n{text}'),
  ('建議標題', '請為以下內容建議 3 個標題，直接列出，不要其他說明：\n\n{text}'),
  ('改得更正式', '請將以下內容改寫成正式、書面的語氣，保留 Markdown 格式：\n\n{text}'),
  ('改得更口語', '請將以下內容改寫成輕鬆口語的語氣，保留 Markdown 格式：\n\n{text}'),
  ('修正錯別字與格式', '請修正以下內容的錯別字、標點與 Markdown 格式問題，只輸出修正後的內容：\n\n{text}'),
];

/// The editor's AI assistant sheet: two tabs — 快捷指令 (presets with an
/// add/remove diff preview) and 自由交流 (multi-turn streaming chat). Both
/// pop `(result, targetRange)` on 套用 so the caller can splice the AI
/// output into the controller.
class AiAssistantSheet extends StatefulWidget {
  final String docText;
  final TextSelection selection;
  final bool hasSelection;

  const AiAssistantSheet({
    super.key,
    required this.docText,
    required this.selection,
    required this.hasSelection,
  });

  @override
  State<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<AiAssistantSheet> {
  /// The text the LLM will process: the selection when there is one,
  /// otherwise the whole document.
  String get _targetText => widget.hasSelection
      ? widget.docText.substring(widget.selection.start, widget.selection.end)
      : widget.docText;

  TextRange get _targetRange => widget.hasSelection
      ? TextRange(start: widget.selection.start, end: widget.selection.end)
      : TextRange(start: 0, end: widget.docText.length);

  void _applyResult(String result) {
    Navigator.of(context).pop((result, _targetRange));
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.border2),
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: c.blue),
                    const SizedBox(width: 8),
                    Text(
                      'AI 助理',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.hasSelection
                          ? '已選取 ${_targetText.length} 字'
                          : '整篇文件',
                      style: TextStyle(color: c.mute, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TabBar(
                  tabs: const [
                    Tab(text: '快捷指令'),
                    Tab(text: '自由交流'),
                  ],
                  labelColor: c.text,
                  unselectedLabelColor: c.dim,
                  indicatorColor: c.blue,
                  dividerColor: c.border,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: TabBarView(
                    children: [
                      _AiPresetTab(
                        targetText: _targetText,
                        onApply: _applyResult,
                      ),
                      _AiChatTab(
                        docText: widget.docText,
                        selection: widget.selection,
                        hasSelection: widget.hasSelection,
                        onApply: _applyResult,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 快捷指令 tab: pick an instruction, wait for the LLM, review the
/// add/remove diff, then 套用.
class _AiPresetTab extends StatefulWidget {
  final String targetText;
  final ValueChanged<String> onApply;

  const _AiPresetTab({required this.targetText, required this.onApply});

  @override
  State<_AiPresetTab> createState() => _AiPresetTabState();
}

class _AiPresetTabState extends State<_AiPresetTab> {
  bool _busy = false;
  bool _showDiff = true;
  String? _error;
  String? _result;

  /// Line-level changes the AI made to [widget.targetText].
  List<DiffHunk> get _diffHunks {
    final result = _result;
    if (result == null) return const [];
    return diffTexts(widget.targetText, result);
  }

  int get _addedCount => diffStats(_diffHunks).$1;
  int get _removedCount => diffStats(_diffHunks).$2;

  Future<void> _run(String instruction) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final useBuiltin = await LlmPrefs.useBuiltin;
      final baseUrl = (await LlmPrefs.baseUrl)!;
      final model = (await LlmPrefs.model)!;
      final apiKey = useBuiltin ? null : await LlmPrefs.apiKey;
      final reply = await LlmClient.complete(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        userPrompt: instruction.replaceFirst('{text}', widget.targetText),
      );
      if (mounted) setState(() => _result = reply);
    } on LlmException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'AI 處理失敗，再試一次看看 (´;ω;`)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply() {
    final result = _result;
    if (result == null) return;
    widget.onApply(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, prompt) in _aiInstructions)
                GestureDetector(
                  onTap: _busy ? null : () => _run(prompt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: c.inset,
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(color: c.text, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: c.border2,
              color: c.blue,
            ),
            const SizedBox(height: 6),
            Text('AI 處理中…', style: TextStyle(color: c.mute, fontSize: 11)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: ItouColors.danger, fontSize: 12),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '新增 $_addedCount 行・刪除 $_removedCount 行',
                  style: TextStyle(color: c.dim, fontSize: 11.5),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showDiff = !_showDiff),
                  child: Text(
                    _showDiff ? '顯示原始文字' : '顯示差異',
                    style: TextStyle(color: c.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.inset,
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                child: _showDiff
                    ? (_diffHunks.isEmpty
                          ? Text(
                              '沒有變更',
                              style: TextStyle(color: c.mute, fontSize: 12),
                            )
                          : DiffView(hunks: _diffHunks, c: c))
                    : Text(
                        _result!,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _apply,
                    child: const Text('套用'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 自由交流 tab: multi-turn chat with streaming replies. The document
/// (and current selection, when there is one) is injected into the system
/// prompt on every turn so the model knows what the user is talking about.
/// History lives only for the lifetime of this sheet — reopening starts a
/// fresh conversation.
class _AiChatTab extends StatefulWidget {
  final String docText;
  final TextSelection selection;
  final bool hasSelection;
  final ValueChanged<String> onApply;

  const _AiChatTab({
    required this.docText,
    required this.selection,
    required this.hasSelection,
    required this.onApply,
  });

  @override
  State<_AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<_AiChatTab> {
  final _messages = <({String role, String content})>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// The document context injected into the system prompt on every turn:
  /// the full document (truncated) plus the current selection, so the model
  /// can answer questions like "把選取的這段改成口語".
  String _contextBlock() {
    const maxDocChars = 6000;
    final doc = widget.docText;
    final truncated = doc.length > maxDocChars
        ? '${doc.substring(0, maxDocChars)}\n…（內容已截斷）'
        : doc;
    final buffer = StringBuffer('以下是使用者正在編輯的文件內容：\n```\n$truncated\n```');
    if (widget.hasSelection) {
      final sel = widget.selection;
      buffer.write(
        '\n目前選取的文字：\n```\n'
        '${widget.docText.substring(sel.start, sel.end)}\n```',
      );
    }
    return buffer.toString();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _busy) return;
    _inputController.clear();
    setState(() {
      _messages.add((role: 'user', content: text));
      _busy = true;
      _error = null;
    });
    _scrollToBottom();

    // Snapshot the history sent to the model before adding the placeholder
    // assistant turn below — that placeholder is UI-only (an empty bubble
    // showing the "thinking" spinner while waiting for the first token) and
    // must never be sent back as part of the conversation.
    final history = List.of(_messages);
    setState(() => _messages.add((role: 'assistant', content: '')));
    _scrollToBottom();

    try {
      final useBuiltin = await LlmPrefs.useBuiltin;
      final baseUrl = (await LlmPrefs.baseUrl)!;
      final model = (await LlmPrefs.model)!;
      final apiKey = useBuiltin ? null : await LlmPrefs.apiKey;
      var reply = '';
      final full = await LlmClient.completeStream(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        messages: history,
        extraSystem: _contextBlock(),
        onDelta: (delta) {
          reply += delta;
          if (!mounted) return;
          setState(() {
            _messages[_messages.length - 1] = (
              role: 'assistant',
              content: reply,
            );
          });
          _scrollToBottom();
        },
      );
      if (!mounted) return;
      setState(() {
        _messages[_messages.length - 1] = (role: 'assistant', content: full);
      });
    } on LlmException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
            _messages.removeLast();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'AI 處理失敗，再試一次看看 (´;ω;`)';
          if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
            _messages.removeLast();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _messages.isEmpty && !_busy
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '跟 AI 自由對話，例如：\n「幫我把這篇改成更口語的語氣」',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.mute,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length + (_error != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: ItouColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    final message = _messages[index];
                    return _ChatBubble(
                      role: message.role,
                      content: message.content,
                      busy:
                          _busy &&
                          index == _messages.length - 1 &&
                          message.role == 'assistant' &&
                          message.content.isEmpty,
                      onApply: message.role == 'assistant'
                          ? () => widget.onApply(message.content)
                          : null,
                      c: c,
                    );
                  },
                ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: TextStyle(color: c.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '輸入訊息…',
                  hintStyle: TextStyle(color: c.mute, fontSize: 13),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '送出',
              icon: Icon(Icons.send, size: 20, color: c.blue),
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String role;
  final String content;
  final bool busy;
  final VoidCallback? onApply;
  final ItouColors c;

  const _ChatBubble({
    required this.role,
    required this.content,
    required this.busy,
    required this.onApply,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser ? c.blue.withValues(alpha: 0.14) : c.inset,
                border: Border.all(
                  color: isUser ? c.blue.withValues(alpha: 0.35) : c.border,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI 思考中…',
                            style: TextStyle(color: c.mute, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  SelectableText(
                    content,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                  if (onApply != null) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onApply,
                      child: Text(
                        '套用到編輯器',
                        style: TextStyle(color: c.blue, fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
