import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/markdown_renderer.dart';
import '../services/update_checker.dart';
import '../theme.dart';

/// Shows the "new version available" dialog and drives the in-app download
/// + install flow. Used both from the settings "檢查更新" row and the silent
/// check on app start.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  UpdateInfo info, {
  required String currentVersion,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info, currentVersion: currentVersion),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final String currentVersion;

  const _UpdateDialog({required this.info, required this.currentVersion});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  // Android 8+ refuses to open the installer without the "install unknown
  // apps" permission; when it's missing we ask the user to enable it first.
  bool _needInstallPermission = false;

  Future<void> _download() async {
    // In-app APK install is Android-only; anywhere else, hand the user to
    // the release page instead.
    if (!Platform.isAndroid) {
      await launchUrl(Uri.parse(widget.info.releaseUrl));
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final url = widget.info.apkUrl;
    if (url == null) {
      setState(() => _error = '這個版本沒有附 APK 檔案 (´;ω;`)');
      return;
    }
    // Check before downloading — a 70MB download wasted on a blocked
    // installer is no fun.
    final canInstall = await InstallHelper.canRequestPackageInstalls();
    if (!mounted) return;
    if (!canInstall) {
      setState(() {
        _needInstallPermission = true;
        _error = null;
      });
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _needInstallPermission = false;
      _error = null;
    });
    try {
      final file = await UpdateChecker.downloadApk(
        url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      try {
        await UpdateChecker.installApk(file);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _error = '開啟安裝介面失敗：$e';
        });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('更新檔已開啟，請完成安裝 (｡•ᴗ•｡)')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下載失敗：$e';
      });
    }
  }

  Future<void> _openInstallSettings() async {
    await InstallHelper.openUnknownAppSourcesSettings();
  }

  @override
  Widget build(BuildContext context) {
    final c = ItouColorsExt.of(context);
    final notes = widget.info.notes ?? '';
    final notesShown = notes.length > 500 ? notes.substring(0, 500) : notes;
    final notesHtml = notesShown.isEmpty
        ? ''
        : convertMarkdownToHtml(notesShown);

    return AlertDialog(
      backgroundColor: c.panel,
      title: const Text('發現新版本'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_alt, size: 18, color: c.blue),
                const SizedBox(width: 8),
                Text(
                  'v${widget.info.latestVersion}',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '目前 v${widget.currentVersion}',
                  style: TextStyle(color: c.mute, fontSize: 12),
                ),
              ],
            ),
            if (notesHtml.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.inset,
                  border: Border.all(color: c.border),
                ),
                // Release notes are Markdown (the GitHub release body);
                // render them properly instead of raw text.
                child: SingleChildScrollView(
                  child: HtmlWidget(
                    notesHtml,
                    textStyle: TextStyle(
                      color: c.dim,
                      fontSize: 12,
                      height: 1.5,
                    ),
                    onTapUrl: (url) async {
                      final uri = Uri.tryParse(url);
                      if (uri != null) await launchUrl(uri);
                      return true;
                    },
                  ),
                ),
              ),
            ],
            if (_needInstallPermission) ...[
              const SizedBox(height: 12),
              Text(
                '需要允許「安裝未知應用程式」，才能開啟安裝介面。',
                style: TextStyle(color: c.dim, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _openInstallSettings,
                  child: const Text('開啟設定'),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: c.border2,
                  color: c.blue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '下載中 ${(_progress * 100).round()}%',
                style: TextStyle(color: c.mute, fontSize: 11),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: ItouColors.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('稍後'),
        ),
        if (!_downloading)
          ElevatedButton(
            onPressed: _needInstallPermission ? null : _download,
            child: const Text('下載並更新'),
          ),
      ],
    );
  }
}
