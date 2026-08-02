<img src="assets\logo\logo_nbg.webp" height=70>
<h1>itouMD</h1>

[![CI](https://github.com/itousouta15/itouMD/actions/workflows/ci.yml/badge.svg)](https://github.com/itousouta15/itouMD/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/itousouta15/itouMD)](https://github.com/itousouta15/itouMD/releases/latest)

一款用於行動裝置的現代化 Markdown 檢視器與編輯器。

## 功能亮點

- **Markdown 渲染**：支援 GitHub Flavored Markdown (GFM)、HackMD 風格容器語法（`:::info`／`:::spoiler` 等）、`[TOC]` 目錄展開、GitHub 風格 `> [!NOTE]` alert。
- **程式碼語法高亮**：fenced code block 標了語言自動上色，隨深淺色主題變換。
- **LaTeX 數學公式**：支援 inline `$...$` 與 display `$$...$$`。
- **本機編輯器**：內建格式工具列（粗體、斜體、標題、清單、引用、連結、程式碼區塊），按 Enter 自動延續清單項目。
- **HackMD 雲端同步**：連結你的 HackMD 帳號後，編輯完可直接同步回雲端。
- **衝突偵測**：同步前自動檢查雲端版本是否在別處被改過，若有變更會跳警告讓你選擇「還是要蓋過去」或取消，避免不慎覆蓋別人的編輯。
- **開啟時自動更新**：點開 HackMD 筆記時自動抓取最新內容，不會拿過期暫存版本蓋掉雲端上的新變更。
- **瀏覽 HackMD 筆記**：可直接從 App 內瀏覽你的 HackMD 個人筆記與各團隊筆記，點選即開，不用貼網址。
- **團隊支援**：完整支援 HackMD 團隊筆記——瀏覽清單、讀取內容、同步回團隊工作區皆可使用。
- **另存新檔**：編輯完可另存成 `.md` 檔案到裝置任意位置。
- **多種來源**：貼上文字、選擇本機檔案（`.md`／`.markdown`／`.mdx`／`.txt`）、從 GitHub／Gist／HackMD 網址擷取內容。
- **閱讀偏好**：可調整字體（MantouSans 等）、字級、文字顏色，設定會自動保存。
- **深淺色主題**：深色／淺色模式切換，帶有平滑動畫過場。
- **最近開啟**：自動保存最近開啟的 Markdown（上限 5 筆），快速回到先前內容。

## 目標使用情境

- 在手機上快速預覽、編輯 Markdown，不用開電腦。
- 直接瀏覽並編輯 GitHub、Gist、HackMD 上的 Markdown 內容，編輯完一鍵同步回 HackMD。
- 在其他裝置或網頁版改過同一篇筆記時，App 能自動提醒，避免互相覆蓋。
- 需要顯示 LaTeX 數學公式與程式碼語法高亮效果。
- 把本機 Markdown 檔案當成輕量閱讀器／編輯器使用。

## 專案架構

```
lib/
├── main.dart                          應用入口，負責主題與首頁初始化
├── theme.dart                         自訂應用主題與顏色樣式
├── screens/
│   ├── home_screen.dart               首頁：貼上、選檔、網址抓取、最近開啟、筆記列表
│   ├── viewer_screen.dart             檢視／編輯頁面：HTML 轉換、公式渲染、
│   │                                  語法高亮、格式工具列、HackMD 同步、衝突偵測
│   ├── hackmd_account_screen.dart     HackMD 帳號（API Token）設定
│   ├── hackmd_notes_screen.dart       瀏覽個人與團隊的 HackMD 筆記清單
│   └── settings_screen.dart           設定頁：外觀主題、HackMD 帳號狀態
├── services/
│   ├── markdown_renderer.dart         Markdown → HTML 轉換管線（isolate 執行）
│   ├── markdown_source.dart           遠端 Markdown 擷取與 URL 正規化
│   ├── markdown_editor_actions.dart   編輯器工具列／清單自動延續的純邏輯
│   ├── hackmd_syntax.dart             HackMD 容器語法、`[TOC]` 展開
│   ├── hackmd_api.dart                HackMD REST API 客戶端（含團隊端點）
│   ├── hackmd_account.dart            HackMD API Token 安全儲存
│   ├── latex_preprocessor.dart        保護 LaTeX 公式避免被 Markdown 解析破壞
│   ├── reader_prefs.dart              保存讀者偏好設定
│   └── recent_docs.dart               儲存與管理最近開啟紀錄
└── widgets/
    └── loader_ring.dart               載入動畫元件與 SectionLabel
```

## 啟動完整流程

### 1. 環境需求

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable channel，需支援 Dart `^3.12.2`，建議使用最新穩定版）
- Android 開發：Android Studio + Android SDK
- iOS 開發（需 macOS）：Xcode + CocoaPods
- 一台實體裝置、Android Emulator 或 iOS Simulator

> Windows 開發者請注意：專案路徑必須是純 ASCII（不能包含中文等非英文字元），否則 Dart 分析伺服器與 Android Gradle 建置都會出問題。詳見 [`DEV_NOTES.md`](DEV_NOTES.md)。

### 2. 取得原始碼

```bash
git clone https://github.com/itousouta15/itouMD.git
cd itouMD
```

### 3. 檢查環境

```bash
flutter doctor
```

確認 Flutter、Android toolchain（或 Xcode）皆為 ✓ 再繼續下一步。

### 4. 安裝相依套件

```bash
flutter pub get
```

### 5. 確認可用裝置

```bash
flutter devices
```

若尚未啟動模擬器，可透過 Android Studio 的 Device Manager 或執行 `open -a Simulator`（macOS，iOS 模擬器）啟動。

### 6. 執行應用（Debug 模式）

```bash
flutter run
```

若偵測到多台裝置，可用 `-d` 指定：

```bash
flutter run -d <device-id>
```

### 7. 執行測試與靜態分析

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

這三步就是 CI（`.github/workflows/ci.yml`）在每次 push/PR 時會跑的檢查，送 PR 前建議先本機跑過一次。

### 8.（選用）建置發布版本

```bash
# Android APK（沒有設定 android/key.properties 時會退回 debug 簽章）
flutter build apk --release

# iOS（需 macOS，簽名設定需在 Xcode 完成）
flutter build ios --release
```

建置產物分別位於 `build/app/outputs/flutter-apk/`（Android）與 `build/ios/`（iOS）。正式發布的簽章金鑰只存在開發者本機與 CI 密鑰中，不會出現在版本庫裡。

## 支援的依賴套件

| 套件 | 用途 |
| --- | --- |
| `markdown` | Markdown → HTML 轉換核心 |
| `flutter_widget_from_html_core` / `fwfh_svg` | HTML 渲染成 Flutter Widget |
| `flutter_math_fork` | LaTeX 數學公式渲染 |
| `flutter_highlight` / `highlight` | 程式碼區塊語法高亮 |
| `flutter_svg` | SVG 圖片渲染 |
| `html` | HTML DOM 解析（自訂 widget builder 用） |
| `http` | 網路請求（URL 擷取、HackMD API） |
| `file_picker` | 選擇本機檔案、另存新檔 |
| `flutter_secure_storage` | HackMD API Token 安全儲存（Android Keystore／iOS Keychain） |
| `shared_preferences` | 閱讀偏好、最近開啟紀錄 |
| `google_fonts` | 閱讀字體 |
| `url_launcher` | 開啟外部連結 |
| `cupertino_icons` | iOS 風格圖示 |

## 使用說明

### 基本操作

1. 打開 App 後可直接「貼上文字」、選擇本機檔案，或貼入網址從 GitHub／Gist／HackMD 擷取內容。
2. 進入檢視頁面後，點右上角編輯圖示切換到編輯模式，畫面下方會出現格式工具列。
3. 編輯完成後點「完成編輯」套用並重新渲染預覽；點「另存新檔」可存成 `.md` 檔案。

### HackMD 同步與衝突防護

4. 到「設定 → HackMD 帳號」貼上你的 [Personal Access Token](https://hackmd.io/@docs/how-to-issue-an-api-token)，測試連線成功即完成連結。
5. 從 HackMD 網址開啟的筆記，檢視頁面會出現雲端同步圖示，點選即可將編輯推回 HackMD。
6. **衝突偵測**：同步前 App 會自動比對雲端版本和開啟時抓到的原始內容——若別處有改過，會彈出對話框讓你選擇「還是要蓋過去」或取消。
7. **自動更新**：每次點開 HackMD 筆記時自動抓取最新內容，確保你看到的是最新版。

### 瀏覽 HackMD 筆記清單

8. 在首頁點「瀏覽我的 HackMD 筆記」，即可看到你的個人筆記與各團隊筆記分類列表，下拉重新整理，點選即可開啟。

### 閱讀偏好

9. 在檢視頁面點選「顯示設定」可調整字體、字級與文字顏色；複製圖示可把原始 Markdown 複製到剪貼簿。
10. 到「設定」頁可切換深色／淺色模式、查看 HackMD 帳號連結狀態。

## 開發備註

- 遠端 URL 擷取會自動將常見 GitHub／Gist／HackMD 連結轉換為 raw／下載格式。
- 最近開啟紀錄儲存在 `SharedPreferences`，最多保存 5 筆。
- LaTeX 公式與 HackMD 圖片縮放語法（`![alt](url =50%x)`）會先經過預處理，避免被標準 Markdown 解析器誤判或忽略。
- HackMD API Token 儲存在系統金鑰庫（Android Keystore／iOS Keychain），不會跟其他偏好設定混在一起。
- HackMD 團隊 API 使用的是 **team path**（`@teamname` 的 `teamname` 部分）而非 UUID——這是根據官方 [`hackmdio/api-client`](https://github.com/hackmdio/api-client) 確認的規格。
- 衝突偵測的 baseline 指的是「Viewer 載入時的原始內容」，**不會**被開啟時的自動更新覆蓋——這樣即使重開筆記、自動拉到最新版，sync 時還是能比對出雲端在載入後發生的變更。
- 更多疑難排解（Windows 路徑限制、模擬器黑屏問題等）請見 [`DEV_NOTES.md`](DEV_NOTES.md)。

## 貢獻

歡迎 PR 與 Issue！送出前請先閱讀 [`CONTRIBUTING.md`](CONTRIBUTING.md)，並遵守 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) 的行為準則。

## 安全性

如果你發現安全性問題，請不要直接開公開 Issue，改參考 [`SECURITY.md`](SECURITY.md) 的回報方式。

## 致謝

- 感謝 [`emfont`](https://font.emtech.cc/) 提供開源字型資源，讓閱讀體驗更豐富。
- 感謝 [`HackMD`](https://hackmd.io/) 的容器語法與 Markdown 協作設計，啟發本專案對 note-style callout 與雲端同步的支援。

## 授權

本專案採用 MIT License。詳細授權內容請參閱 [`LICENSE`](LICENSE) 檔案。
