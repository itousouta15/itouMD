import 'package:flutter/material.dart';

import '../theme.dart';

/// First-launch wizard: four pages introducing what itouMD does, shown once
/// before the home screen. Skipping or finishing records the flag so it
/// never appears again.
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

const _pages = [
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
    title: 'HackMD 雲端同步',
    description:
        '瀏覽你的個人與團隊筆記，開啟時自動更新；'
        '同步前會比對雲端版本，衝突時讓你自己選擇保留哪一邊。',
    icon: Icons.cloud_outlined,
  ),
  _OnboardingPage(
    title: '你的閱讀，你做主',
    description:
        '字體、字級、文字顏色自由調整，'
        '自訂調色盤；介面字級與深淺色主題也能隨心切換。',
    icon: Icons.palette_outlined,
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _enterCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  int _page = 0;

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

  bool get _isLast => _page == _pages.length - 1;

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
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) => _OnboardingPageView(
                  page: _pages[index],
                  animation: _enterCtrl,
                  index: index,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
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
