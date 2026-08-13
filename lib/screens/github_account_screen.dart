import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/github_account.dart';
import '../services/github_api.dart';
import '../services/github_oauth.dart';
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

  Future<void> _loginWithAccount() async {
    if (!GithubOAuth.isConfigured) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await GithubOAuth.startDeviceFlow();
      if (!mounted) return;
      setState(() => _busy = false);

      final token = await _showDeviceCodeDialog(session);
      if (token == null) return; // cancelled

      final login = await GithubApi.getAuthenticatedUser(token);
      await GithubAccount.setToken(token);
      _tokenController.text = token;
      if (!mounted) return;
      setState(() => _connectedUser = login);
    } on GithubOAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GithubApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '登入失敗，再試一次看看 (´;ω;`)');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  /// Shows the device code in a dialog and polls until the user authorizes.
  /// Returns the access token, or null if the dialog was cancelled.
  Future<String?> _showDeviceCodeDialog(GithubOAuthSession session) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DeviceCodeDialog(session: session),
    );
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
            if (GithubOAuth.isConfigured) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _loginWithAccount,
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('使用 GitHub 帳號登入'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '推薦：用帳號登入，不需另外建立 Token。',
                style: TextStyle(color: c.mute, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Text(
                '進階：手動 Personal Access Token',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
            ] else
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

/// The device-flow dialog: shows the user code (tap to copy) and a button
/// to open GitHub's verification page, then polls for the token itself as
/// soon as it's shown — not gated behind the dialog closing, since that
/// would mean polling only starts *after* the user already cancelled.
class _DeviceCodeDialog extends StatefulWidget {
  final GithubOAuthSession session;

  const _DeviceCodeDialog({required this.session});

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    try {
      final token = await GithubOAuth.pollForToken(
        widget.session,
        isCancelled: () => _cancelled,
      );
      if (mounted) Navigator.of(context).pop(token);
    } on GithubOAuthException catch (e) {
      if (mounted && !_cancelled) setState(() => _error = e.message);
    }
  }

  void _cancel() {
    _cancelled = true;
    Navigator.of(context).pop();
  }

  void _copyUserCode() {
    Clipboard.setData(ClipboardData(text: widget.session.userCode));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已複製代碼')));
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return AlertDialog(
      backgroundColor: c.panel,
      title: const Text('使用 GitHub 帳號登入'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '在 GitHub 上輸入這個代碼完成授權：',
              style: TextStyle(color: c.dim, fontSize: 13),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _copyUserCode,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.session.userCode,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 34,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_outlined, size: 18, color: c.mute),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(widget.session.verificationUri),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('開啟 GitHub 授權頁面'),
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: ItouColors.danger, fontSize: 12),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('等待授權…', style: TextStyle(color: c.mute, fontSize: 12)),
                ],
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: _cancel, child: const Text('取消'))],
    );
  }
}
