import 'package:flutter/material.dart';

import '../services/github_account.dart';
import '../services/hackmd_account.dart';
import '../theme.dart';
import 'github_account_screen.dart';
import 'hackmd_account_screen.dart';

/// First-launch wizard: three intro pages plus two account-link pages
/// (HackMD, GitHub), shown once before the home screen. Skipping or
/// finishing records the flag so it never appears again.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final String title;
  final String description;
  final IconData icon;

  const _OnboardingPage({
    required this.title,
    required this.description,
    required this.icon,
  });
}

const _introPages = [
  _OnboardingPage(
    title: '手機也能好好用 MD',
    description:
        '輕量的 Markdown 閱讀器與編輯器，'
        '支援 GitHub 風格語法、LaTeX 公式、程式碼高亮，'
        '隨時隨地打開就能看、就能寫。',
    icon: Icons.auto_stories_outlined,
  ),
  _OnboardingPage(
    title: '多種來源，一個入口',
    description:
        '直接貼上文字、開啟本機 .md 檔案，'
        '或貼上 GitHub／Gist／HackMD 網址抓取內容。',
    icon: Icons.link_outlined,
  ),
  _OnboardingPage(
    title: '雲端整合：HackMD 與 GitHub',
    description:
        '瀏覽個人與團隊筆記、衝突合併、同步回 HackMD；'
        '從 GitHub 開啟的文件也能直接寫回 repo。',
    icon: Icons.cloud_outlined,
  ),
];

const _pageCount = 5;

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _enterCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  int _page = 0;
  int _loginTick = 0;

  @override
  void initState() {
    super.initState();
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pageCount - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int i) {
    setState(() {
      _page = i;
      // Re-check the account status whenever a login page becomes visible.
      if (i >= 3) _loginTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text(
                    '跳過',
                    style: TextStyle(color: c.mute, fontSize: 13),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  if (index < _introPages.length) {
                    return _OnboardingPageView(
                      page: _introPages[index],
                      animation: _enterCtrl,
                      index: index,
                    );
                  }
                  return _LoginPage(
                    account: index == 3
                        ? _LoginAccount.hackmd
                        : _LoginAccount.github,
                    animation: _enterCtrl,
                    index: index,
                    refreshTick: _loginTick,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: i == _page ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: i == _page ? c.blue : c.border2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                // No fixed height — a tall UI text scale would clip the
                // label; padding grows with the text instead.
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _next,
                  child: Text(_isLast ? '開始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LoginAccount { hackmd, github }

/// Account-link page: shows whether the account is connected, offers the
/// login button (which pushes the account screen), and re-checks the status
/// when the page becomes visible or after returning from the account screen.
class _LoginPage extends StatefulWidget {
  final _LoginAccount account;
  final Animation<double> animation;
  final int index;
  final int refreshTick;

  const _LoginPage({
    required this.account,
    required this.animation,
    required this.index,
    required this.refreshTick,
  });

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  bool _connected = false;

  bool get _isHackmd => widget.account == _LoginAccount.hackmd;

  Future<void> _check() async {
    final token = _isHackmd
        ? await HackmdAccount.getToken()
        : await GithubAccount.getToken();
    if (!mounted) return;
    setState(() => _connected = token != null && token.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _check();
  }

  Future<void> _login() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _isHackmd
            ? const HackmdAccountScreen()
            : const GithubAccountScreen(),
      ),
    );
    if (mounted) _check();
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final start = (widget.index * 0.14).clamp(0.0, 0.4);
    final anim = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(
        start,
        (start + 0.6).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(anim),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  _isHackmd ? Icons.cloud_outlined : Icons.code,
                  size: 56,
                  color: c.blue,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _isHackmd ? '連結 HackMD' : '連結 GitHub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _isHackmd
                    ? '連結後可以瀏覽筆記、同步與合併回雲端。'
                    : '連結後可以從 GitHub 網址開啟文件並直接寫回 repo。',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.7),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _connected
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: _connected ? ItouColors.success : c.mute,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _connected ? '已連結' : '尚未連結',
                    style: TextStyle(
                      color: _connected ? ItouColors.success : c.mute,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _login,
                  icon: Icon(_isHackmd ? Icons.login : Icons.login, size: 18),
                  label: Text(_isHackmd ? '登入 HackMD' : '使用 GitHub 帳號登入'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '也可以之後在「設定」裡連結',
                style: TextStyle(color: c.mute, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  final Animation<double> animation;
  final int index;

  const _OnboardingPageView({
    required this.page,
    required this.animation,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final start = (index * 0.14).clamp(0.0, 0.4);
    final anim = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.6).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(anim),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(page.icon, size: 56, color: c.blue),
              ),
              const SizedBox(height: 28),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                page.description,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
