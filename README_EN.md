<img src="assets\logo\logo_nbg.webp" height=70>
<h1>itouMD</h1>

[![CI](https://github.com/itousouta15/itouMD/actions/workflows/ci.yml/badge.svg)](https://github.com/itousouta15/itouMD/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/itousouta15/itouMD)](https://github.com/itousouta15/itouMD/releases/latest)

**繁體中文：[README.md](README.md)**

A modern Markdown viewer and editor for mobile devices, deeply integrated with HackMD.

## Screenshots

| Onboarding | Home | Viewer |
| --- | --- | --- |
| ![Onboarding](docs/screenshots/01-onboarding.png) | ![Home](docs/screenshots/02-home.png) | ![Viewer](docs/screenshots/03-viewer.png) |

| Editor | Notes list | Settings |
| --- | --- | --- |
| ![Editor](docs/screenshots/04-editor.png) | ![HackMD notes](docs/screenshots/05-notes.png) | ![Settings](docs/screenshots/06-settings.png) |

## Features

### Reading & Editing

- **Markdown rendering**: GitHub Flavored Markdown (GFM), HackMD-style containers (`:::info` / `:::spoiler`, etc.), `[TOC]` expansion, GitHub-style `> [!NOTE]` alerts.
- **Code blocks**: automatic syntax highlighting by language, with **line numbers** and a **one-tap copy** button.
- **LaTeX math**: inline `$...$` and display `$$...$$`.
- **Images**: tap to open fullscreen with pinch-to-zoom (SVG badges render correctly too).
- **Built-in editor**: formatting toolbar (bold, italic, headings, lists, quotes, links, code blocks), Enter auto-continues list items; a **line-number gutter** that scrolls in sync with the text, and after leaving edit mode the preview **scrolls back to the line you were editing**.
- **Multiple sources**: **create a new document** (type a title and start writing; when a HackMD account is linked you can also create it as a cloud note), paste text, open local files (`.md` / `.markdown` / `.mdx` / `.txt`), or fetch from GitHub / Gist / HackMD URLs.
- **Reader preferences**: fonts (8 built-in + **import your own**), font size, text color (9 presets + a **custom color picker**); settings are saved automatically.
- **UI text scale**: Standard / Large / Extra-large; the reader content keeps its own independent size control.
- **Theme system**: **follow the system** (or pick light / dark manually) with smooth animated transitions; **theme colors** can be customized per theme — accent (buttons, links) and background (an "auto" option derives a tinted background from the accent, or pick any color; panel tones are derived automatically and text contrast adapts to the background brightness).
- **Save as**: export edited content as a `.md` file anywhere on the device.

### HackMD Cloud

- **Browse my HackMD notes**: grouped list of personal and team notes (collapsible sections) — tap to open, no URL pasting.
- **Team support**: full support for HackMD team workspaces — browse, read, and sync back to team notes.
- **Auto-refresh on open**: HackMD notes fetch the latest content automatically when opened.
- **Conflict merge**: sync compares the cloud version first; when it changed elsewhere, a **three-way merge screen** shows the diff — non-conflicting remote changes are merged automatically, and conflicting regions let you pick "keep local" or "keep remote" per block.
- **Undo sync**: within 10 seconds of a successful sync you can restore the previous cloud version (works even across app restarts).
- **Sync history**: last 50 syncs stored locally (time / note / merged or overwritten).
- **Offline cache**: browse lists and note contents are cached; reading works offline with an "offline version" badge.

### AI Assistant

- **Preset instructions**: polish, translate to Traditional Chinese or English, condense, rewrite, summarize, expand, convert to a table or a list, suggest titles, make it more formal or casual, fix typos and formatting — **13 commands**, each with a concrete prompt template.
- **Add/remove diff preview**: before applying, the result shows how many lines were added/removed and a full line-level diff (red removed / green added).
- **Free conversation**: a chat tab with multi-turn conversation and **streaming** replies; the full document and the current selection are injected into every turn, so the AI actually knows what you're talking about.
- **Multiple entry points**: an AppBar button in edit mode, a highlighted toolbar button, and a "AI assistant" item in the text-selection menu.

### GitHub

- **Account login via OAuth device flow** — authorize on GitHub, no token creation needed (manual PAT stays as an advanced option).
- **Write back**: files opened from GitHub URLs (blob pages or repo roots) can be edited and pushed back to the repo, with 409-safe three-way conflict handling and an undo action.
- **Open a repo from home**: type `owner/repo` (or paste a full URL) to open the README directly; private repos work when signed in.

### Other

- **Onboarding wizard**: 5 pages on first launch — 3 intro pages plus guided **HackMD and GitHub sign-in** (with connection status); can be replayed any time from Settings → More → Replay intro.
- **In-app updates**: checks for new versions on startup (and manually via Settings → More → Check for updates); Android downloads the APK for system installation, while iOS opens the GitHub Release page.
- **Crash reporting**: Sentry collects crashes (DSN injected at build time, never committed).
- **Recents**: last 5 opened documents kept for quick access.

## Target Use Cases

- Preview and edit Markdown on the go.
- Browse and edit Markdown from GitHub, Gist, or HackMD, then push changes back to HackMD or GitHub in one tap.
- When the same note was edited elsewhere (another device or the web), the app warns you and lets you merge change-by-change instead of silently overwriting.
- Reading documents with LaTeX math and syntax-highlighted code.
- Using local Markdown files as a lightweight reader / editor.

## Downloads and Installation

- **Android**: download the release-signed APK from the [Latest Release](https://github.com/itousouta15/itouMD/releases/latest). Updates must keep the same signing key to install over an existing version.
- **iOS/iPadOS preview**: GitHub Prereleases contain an unsigned asset whose filename ends in `unsigned.ipa`. It cannot be installed directly; re-sign it with your own Apple ID/team first. A free Personal Team profile expires periodically and is suitable for personal testing, not App Store, TestFlight, or public Ad Hoc distribution.
- After downloading the IPA and `SHA256SUMS`, run `shasum -a 256 -c SHA256SUMS` to verify integrity. See [`docs/IOS_DEVELOPMENT.md`](docs/IOS_DEVELOPMENT.md#5-github-release-ios-預覽發布) for signing constraints and the release workflow.

## Project Structure

```
lib/
├── main.dart                          App entry: Sentry, theme (system / custom accent & background), UI scale, home / onboarding
├── theme.dart                         Custom theme & color styles (accent / background derivation)
├── screens/
│   ├── home_screen.dart               Home: new doc, paste, file picker, URL fetch, recents, silent update check, GitHub repo entry
│   ├── onboarding_screen.dart         First-launch wizard (5 pages incl. account sign-in guidance)
│   ├── viewer_screen.dart             Viewer / editor: rendering, line-number editor, toolbar, sync, conflict merge, undo, offline, AI assistant
│   ├── conflict_screen.dart           Conflict merge screen: diff view, per-block choices, merged preview
│   ├── hackmd_notes_screen.dart       Browse personal & team notes (collapsible sections, offline cache)
│   ├── hackmd_account_screen.dart     HackMD account (API token) setup
│   ├── github_account_screen.dart     GitHub account (OAuth device flow / PAT) setup
│   ├── sync_history_screen.dart       Sync history list
│   └── settings_screen.dart           Settings: appearance (theme / theme colors), reader prefs, sync, accounts, data, more, about
├── services/
│   ├── markdown_renderer.dart         Markdown → HTML pipeline (runs in an isolate)
│   ├── markdown_source.dart           Remote Markdown fetching & URL normalization
│   ├── markdown_editor_actions.dart   Editor toolbar / list-continuation pure logic
│   ├── markdown_diff.dart             Myers diff & three-way merge (pure Dart, unit-tested)
│   ├── hackmd_syntax.dart             HackMD container syntax, [TOC] expansion
│   ├── hackmd_api.dart                HackMD REST API client (incl. team endpoints, note creation)
│   ├── hackmd_account.dart            HackMD API token secure storage
│   ├── github_api.dart                GitHub REST API client (contents write-back)
│   ├── github_account.dart            GitHub token secure storage
│   ├── github_oauth.dart              GitHub OAuth device flow
│   ├── note_cache.dart                Offline cache (note contents & browse list)
│   ├── sync_history.dart              Sync history & undo slot (cross-session)
│   ├── sync_prefs.dart                Sync preferences (auto-refresh, conflict default)
│   ├── ui_prefs.dart                  UI text scale setting
│   ├── theme_prefs.dart               Theme customization (light/dark accent & background)
│   ├── custom_fonts.dart              Font import: file copy, FontLoader registration, replay on startup
│   ├── llm_client.dart                OpenAI-compatible chat client (streaming SSE)
│   ├── llm_prefs.dart                 AI assistant settings (built-in quota / custom API)
│   ├── update_checker.dart            GitHub Releases update check & install
│   ├── latex_preprocessor.dart        Protects LaTeX from Markdown mis-parsing
│   ├── reader_prefs.dart              Reader preferences (incl. custom color, imported font)
│   └── recent_docs.dart               Recent documents storage
└── widgets/
    ├── loader_ring.dart               Loading spinner & SectionLabel
    ├── diff_view.dart                 Shared line-level diff view (AI preview)
    ├── hsv_color_picker.dart          Shared HSV custom color picker (theme, reader text)
    ├── reader_font_picker.dart        Shared font picker (built-in + imported)
    └── update_dialog.dart             Update dialog (download progress)
```

## Getting Started

### 1. Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, Dart `^3.12.2`, latest stable recommended)
- Android development: Android Studio + Android SDK
- iOS development (macOS only): Xcode + CocoaPods
- A physical device, Android Emulator, or iOS Simulator

> Windows developers: the project path must be pure ASCII (no non-English characters) or the Dart analysis server and Android Gradle builds will fail. See [`DEV_NOTES.md`](DEV_NOTES.md).

### 2. Get the source

```bash
git clone https://github.com/itousouta15/itouMD.git
cd itouMD
```

### 3. Check the environment

```bash
flutter doctor
```

Make sure Flutter and the Android toolchain (or Xcode) all show ✓ before continuing.

### 4. Install dependencies

```bash
flutter pub get
```

### 5. Pick a device

```bash
flutter devices
```

If the emulator isn't running, start it via Android Studio's Device Manager, or run `open -a Simulator` (macOS, iOS).

### 6. Run the app (debug)

```bash
flutter run
```

With multiple devices attached, target one with `-d`:

```bash
flutter run -d <device-id>
```

Enable crash reporting (optional) with a `--dart-define`:

```bash
flutter run --dart-define=SENTRY_DSN=https://xxxx@o000.ingest.sentry.io/0000000
```

### 7. Tests & static analysis

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

These three steps are exactly what CI (`.github/workflows/ci.yml`) runs on every push/PR — run them locally before submitting.

### 8. (Optional) Build a release

```bash
# Android APK (falls back to debug signing when android/key.properties is absent)
flutter build apk --release

# iOS (macOS only; signing must be configured in Xcode)
flutter build ios --release
```

Artifacts land in `build/app/outputs/flutter-apk/` (Android) and `build/ios/` (iOS). Release signing keys live only on the developer's machine and in CI secrets — never in the repository.

### 9. (Optional) Release-signed APKs from CI

The `Build-Android` job in `.github/workflows/ci.yml` builds and uploads the APK artifact. To get a **release-signed** APK from CI, configure these repository secrets (Settings → Secrets and variables):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The keystore file base64-encoded (e.g. `[Convert]::ToBase64String([IO.File]::ReadAllBytes("keystore.jks"))`) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

Without the secrets, CI falls back to debug signing and still builds fine.

## Dependencies

| Package | Purpose |
| --- | --- |
| `markdown` | Markdown → HTML core |
| `flutter_widget_from_html_core` / `fwfh_svg` | HTML rendered as Flutter widgets |
| `flutter_math_fork` | LaTeX math rendering |
| `flutter_highlight` / `highlight` | Code block syntax highlighting |
| `flutter_svg` | SVG rendering |
| `html` | HTML DOM parsing (custom widget builders) |
| `http` | Network requests (URL fetch, HackMD API, update check, LLM) |
| `file_picker` | Pick local files, save as |
| `flutter_secure_storage` | HackMD / GitHub token storage (Android Keystore / iOS Keychain) |
| `shared_preferences` | Preferences, recents, offline cache, sync history |
| `google_fonts` | Reading fonts |
| `url_launcher` | Open external links |
| `package_info_plus` | Current version (update check) |
| `path_provider` / `open_filex` | In-app updates: download APK, invoke the system installer |
| `sentry_flutter` | Crash reporting |
| `cupertino_icons` | iOS-style icons |

## Usage Guide

### First launch

1. The first run shows a 5-page wizard: 3 intro pages plus guided HackMD and GitHub sign-in (each shows its connection status; you can skip them and connect later). Finish with "Get started" or skip from the top-right. Replay anytime from Settings → More → Replay intro.

### Basic operations

2. On the home screen, tap "New document" and enter a title to start writing; or paste text, pick a local file, or fetch from a GitHub / Gist / HackMD URL. You can also type `owner/repo` under "Open GitHub repo" to load a README directly.
3. In the viewer, tap the edit icon to switch to edit mode — a line-number gutter appears on the left and the formatting toolbar docks above the keyboard.
4. Tap "Done" to apply and re-render; the preview scrolls back to the line you were editing. "Save as" exports a `.md` file.
5. Tap the copy icon on a code block to copy the whole block; tap any image for a fullscreen view.

### HackMD sync & conflict merge

6. Go to Settings → HackMD account and paste your [Personal Access Token](https://hackmd.io/@docs/how-to-issue-an-api-token); a successful test links the account.
7. Notes opened from hackmd.io URLs show a cloud-sync icon in the viewer — tap to push your edits back.
8. **Conflict merge**: if the cloud note changed elsewhere, a merge screen opens — remote additions/deletions are shown line by line and merged automatically, while regions both sides edited let you pick "keep local" or "keep remote" before "Merge & sync" (or "Overwrite with local").
9. **Undo**: the success snackbar offers an "Undo" action (10 s) that restores the previous cloud content; Settings → HackMD sync → Sync history lists past syncs.
10. The conflict default (ask every time / overwrite / cancel) and the open-time auto-refresh toggle live in Settings → HackMD sync.

### Browse HackMD notes

11. Home → "Browse my HackMD notes" shows personal and team sections (collapsed by default — tap a header to expand). Pull down to refresh; offline shows the last cached list with an "offline data" badge.

### AI assistant

12. In edit mode, tap the ✨ AI button (AppBar or the highlighted toolbar button), or select text and pick "AI assistant" from the menu.
13. The **Presets** tab offers 13 one-shot commands; results show an add/remove diff before you apply.
14. The **Chat** tab is a free-form, multi-turn conversation with streaming replies; it always knows the document (and your selection), so questions like "make the selected part more casual" work directly. Apply any reply to the editor with the per-message "Apply to editor" link.
15. AI connection settings live in Settings → AI assistant (built-in free quota via `llm.itousouta.me` or your own OpenAI-compatible endpoint + key; test the connection there).

### GitHub

16. Settings → GitHub account → "Sign in with GitHub" authorizes via the OAuth device flow (enter the code at github.com/login/device). Private-repo READMEs and write-back work once signed in.
17. Files opened from `github.com` URLs (blob pages or repo roots) show a "Write back to GitHub" button; conflicts are detected via the file SHA and a merge screen.

### Reading & appearance

18. In the viewer, "Display settings" adjusts fonts (including **imported custom fonts** — `.ttf` / `.otf`), font size, and text color (including a custom color picker).
19. Settings → Appearance: theme (follow system / light / dark), per-theme accent and background colors ("auto" derives a tinted background from the accent; panel tones and text contrast adapt automatically), and UI text scale (Standard / Large / Extra-large). Data management (clear recents / offline cache) is also here.

### In-app updates

20. New versions are announced on startup and can be checked manually at Settings → More → Check for updates. "Download & update" downloads and hands the APK to the system installer in place.

## Development Notes

- Remote URL fetching normalizes common GitHub / Gist / HackMD links to raw/download equivalents.
- Recents are stored in `SharedPreferences`, capped at 5 entries.
- LaTeX and HackMD image-resize syntax (`![alt](url =50%x)`) are preprocessed so the standard Markdown parser can't mangle them.
- HackMD and GitHub tokens live in the system keychain (Android Keystore / iOS Keychain), separate from ordinary preferences.
- The HackMD team API addresses notes by **team path** (the `teamname` in `@teamname`) rather than a UUID — verified against the official [`hackmdio/api-client`](https://github.com/hackmdio/api-client).
- The conflict-merge baseline is the content the viewer was loaded with; the open-time auto-refresh deliberately does not update it, so a note edited after load still triggers the warning even after reopening. The merge algorithm is a hand-rolled Myers diff + three-way merge (`markdown_diff.dart`, unit-tested).
- Update checks use GitHub `releases/latest` and only prompt when the remote version is strictly newer.
- Sentry's DSN is injected via `--dart-define=SENTRY_DSN=...`; without it the SDK is skipped entirely. `SENTRY_ENV` sets the environment tag.
- The UI text scale applies a global `TextScaler`; the reader content and editor opt out so their own size settings stay authoritative.
- Theme accents (`withAccent`) and backgrounds (`withBackground`) derive companion tones in `theme.dart` with HSL offsets; background luminance switches text/border tokens so readability holds for any custom color. Settings persist via `theme_prefs.dart`.
- Imported fonts use Flutter's `FontLoader` (process-wide registration): `custom_fonts.dart` replays saved files on startup so the choice survives restarts; font files are copied into the app documents directory.
- "New document" tries HackMD's `POST /notes` when an account is linked (some tokens/plans may reject it — it falls back to a local draft with a notice).
- More troubleshooting (Windows path limits, emulator black-screen issues, etc.): see [`DEV_NOTES.md`](DEV_NOTES.md).

## Contributing

PRs and issues are welcome! Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) first and follow the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Security

If you find a security issue, don't file a public issue — report it as described in [`SECURITY.md`](SECURITY.md).

## Acknowledgments

- Thanks to [`emfont`](https://font.emtech.cc/) for open-source fonts that make reading nicer.
- Thanks to [`HackMD`](https://hackmd.io/) for its container syntax and collaborative Markdown design, which inspired this project's note-style callouts and cloud sync.

## License

MIT License — see the [`LICENSE`](LICENSE) file.
