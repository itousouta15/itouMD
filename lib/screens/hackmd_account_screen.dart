import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hackmd_account.dart';
import '../services/hackmd_api.dart';
import '../theme.dart';

class HackmdAccountScreen extends StatefulWidget {
  const HackmdAccountScreen({super.key});

  @override
  State<HackmdAccountScreen> createState() => _HackmdAccountScreenState();
}

class _HackmdAccountScreenState extends State<HackmdAccountScreen> {
  final _tokenController = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  HackmdUser? _connectedUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = await HackmdAccount.getToken();
    if (token == null || token.isEmpty) return;
    _tokenController.text = token;
    _testConnection(silent: true);
  }

  Future<void> _testConnection({bool silent = false}) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      if (!silent) setState(() => _error = '請先貼上 API Token');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await HackmdApi.getMe(token);
      await HackmdAccount.setToken(token);
      if (mounted) setState(() => _connectedUser = user);
    } on HackmdApiException catch (e) {
      if (mounted) {
        setState(() {
          _connectedUser = null;
          if (!silent) _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectedUser = null;
          if (!silent) _error = '連線失敗，再試一次看看 (´;ω;`)';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await HackmdAccount.clearToken();
    _tokenController.clear();
    setState(() {
      _connectedUser = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('HackMD 帳號')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '連結你的 HackMD 帳號後，從 HackMD 網址開啟的筆記編輯完可以直接同步回雲端，不用再另存新檔搬來搬去。',
              style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (_connectedUser != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: c.blue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '已連結：${_connectedUser!.name ?? _connectedUser!.email ?? '(未知帳號)'}',
                        style: TextStyle(color: c.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Personal Access Token',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _tokenController,
              obscureText: _obscure,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: '貼上你的 HackMD API Token',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://hackmd.io/@docs/how-to-issue-an-api-token'),
              ),
              child: Text(
                '怎麼取得 Token？',
                style: TextStyle(color: c.blue, fontSize: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: ItouColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _testConnection(),
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('測試並儲存'),
                  ),
                ),
                if (_connectedUser != null) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _disconnect,
                    child: const Text('登出'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
