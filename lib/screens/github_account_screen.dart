import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/github_account.dart';
import '../services/github_api.dart';
import '../theme.dart';

class GithubAccountScreen extends StatefulWidget {
  const GithubAccountScreen({super.key});

  @override
  State<GithubAccountScreen> createState() => _GithubAccountScreenState();
}

class _GithubAccountScreenState extends State<GithubAccountScreen> {
  final _tokenController = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _connectedUser;

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
    final token = await GithubAccount.getToken();
    if (token == null || token.isEmpty) return;
    _tokenController.text = token;
    _testConnection(silent: true);
  }

  Future<void> _testConnection({bool silent = false}) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      if (!silent) setState(() => _error = '請先貼上 Personal Access Token');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await GithubApi.getAuthenticatedUser(token);
      await GithubAccount.setToken(token);
      if (mounted) setState(() => _connectedUser = login);
    } on GithubApiException catch (e) {
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
    await GithubAccount.clearToken();
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
      appBar: AppBar(title: const Text('GitHub 帳號')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '連結 GitHub 帳號後，從 GitHub 網址開啟的文件（blob 頁面或 repo 首頁）'
              '編輯完可以直接寫回，不用再另外開瀏覽器。需要 repo 的寫入權限。',
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
                        '已連結：$_connectedUser',
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
                hintText: '貼上你的 GitHub Token',
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
                Uri.parse(
                  'https://docs.github.com/en/authentication/'
                  'keeping-your-account-and-data-secure/'
                  'managing-your-personal-access-tokens',
                ),
              ),
              child: Text(
                '怎麼取得 Token？（需 repo 寫入權限）',
                style: TextStyle(color: c.blue, fontSize: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFE0777A), fontSize: 13),
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
