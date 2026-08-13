# iOS 開發與側載驗證

這份 runbook 說明 itouMD 在 iOS 的建置、模擬器測試與開發用實機側載流程。它不包含 App Store 發布憑證或任何個人 Team ID。

## 專案基線

| 項目 | 設定 |
| --- | --- |
| Flutter package | `itou_md` |
| App 版本 | 由 `pubspec.yaml` 的 `version` 決定 |
| Bundle identifier | `me.itousouta.itouMd` |
| 最低 iOS 版本 | iOS 13.0 |
| Xcode workspace | `ios/Runner.xcworkspace` |
| 原生相依管理 | Flutter SPM + CocoaPods fallback |

`open_filex` 用於 Android APK 安裝，但目前不支援 Flutter 的 iOS Swift Package Manager。因此 iOS 仍需要 CocoaPods；不要刪除 `ios/Podfile`、`Podfile.lock` 或 xcconfig 裡的 Pods include，直到該相依移除或完成 SPM 支援。

## 1. 環境檢查

```bash
flutter doctor -v
pod --version
xcodebuild -version
xcrun simctl list devices available
flutter devices
```

必須確認：

- Flutter／Dart 版本符合 `pubspec.yaml`。
- Xcode 已完成首次啟動與 license，同時安裝至少一個 iOS Platform/Simulator runtime。
- CocoaPods 可執行。Homebrew 環境可用 `brew install cocoapods` 安裝。
- 實機側載時，`flutter devices` 或 `xcrun devicectl list devices` 看得到已解鎖、信任並啟用 Developer Mode 的 iPhone/iPad。

## 2. 取得相依與無簽章編譯

```bash
flutter pub get
flutter build ios --debug --no-codesign
```

這一步驗證 Dart AOT/JIT 產物、Flutter engine、Swift/Objective-C 外掛、Pods 與 Xcode linker；不需要 Apple 帳號，也不能代表 App 已可安裝到實機。

若 Xcode 回報沒有 iOS Platform，可從 Xcode → Settings → Components 安裝，或執行：

```bash
xcodebuild -downloadPlatform iOS
```

## 3. Simulator 開發測試

先從 Xcode 啟動 Simulator，或建立／啟動一台可用裝置，接著：

```bash
xcrun simctl list devices available
flutter devices
flutter run -d <simulator-id> --debug
```

Simulator 不驗證 Apple code signing、真實 Keychain access group、相機／檔案權限細節與實機效能，因此仍需完成下一節。

## 4. 開發用實機側載

1. 使用 USB 或 Xcode 支援的網路方式連接 iPhone/iPad，在裝置上完成信任與 Developer Mode。
2. 開啟 `ios/Runner.xcworkspace`，選 Runner target → Signing & Capabilities。
3. 啟用 Automatically manage signing，選擇自己的 Apple Development Team。
4. 若既有 bundle identifier 不屬於該 Team，僅在本機簽章設定或專用開發 configuration 使用唯一 identifier；不要提交個人 Team ID。
5. 在 Xcode 選取實機並 Run，或取得 device id 後執行：

```bash
flutter devices
flutter run -d <device-id> --debug
```

Xcode 選好 Team 後，將 Team ID 放在不進版控的本機設定，避免它留在 `project.pbxproj`：

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
# 編輯 Local.xcconfig，把 YOUR_TEAM_ID 換成自己的 Team ID
```

`Debug.xcconfig` 與 `Release.xcconfig` 會選擇性載入這個檔案；其他開發者與無簽章 CI 不需要共用個人 Team ID。

若只要安裝既有已簽章產物，可用 `flutter install -d <device-id>`。安裝成功後仍需在裝置上實際開啟 App，確認沒有啟動畫面後 crash 或簽章信任錯誤。

Debug App 在 iOS 14 以上只能由 Flutter tooling、具 Flutter plugin 的 IDE 或 Xcode 啟動；工具結束後手動點 Debug App 會看到限制訊息。需要像一般側載 App 一樣獨立開啟時，安裝 Release 版：

```bash
flutter run -d <device-id> --release --no-resident
```

## 5. GitHub Release iOS 預覽發布

目前 repository 沒有 Apple distribution certificate／profile，也沒有可延續 Android 正式版的 keystore。為避免公開個人簽章材料，並避免只含 IPA 的新版本取代 Android 使用的 `releases/latest`，iOS 先以 GitHub **Prerelease** 發布無簽章 IPA：

- Tag 格式為 `v<pubspec-version>-ios.<序號>`，例如 app `1.3.0+6` 對應 `v1.3.0-ios.1`。
- `.github/workflows/ios-release.yml` 在 macOS runner 執行 `flutter build ios --release --no-codesign`，確認 App 不含 provisioning profile 且未簽章，再封裝為 `itouMD-<tag>-unsigned.ipa`。
- Release 同時附 `SHA256SUMS`，並固定標為 Prerelease、`latest=false`。因此 Android 版的更新檢查仍停留在最近的穩定 Release。
- IPA 只包含可重新簽章的 `Payload/Runner.app`；不得加入 Personal Team、development 或 distribution 憑證、私鑰及 provisioning profile。

發布前先更新 `pubspec.yaml` 並完成 PR／CI。合併到 `master` 後建立 annotated tag：

```bash
git switch master
git pull --ff-only
git tag -a v1.3.0-ios.1 -m "iOS preview v1.3.0-ios.1"
git push origin v1.3.0-ios.1
```

Tag push 會建置並建立 GitHub Prerelease。若發布 job 暫時失敗，可在 Actions 手動重跑 `iOS GitHub Release`，輸入同一個既存 tag；workflow 會覆寫同名資產。下載後核對：

```bash
shasum -a 256 -c SHA256SUMS
unzip -l itouMD-v1.3.0-ios.1-unsigned.ipa | head
```

無簽章 IPA **不能直接安裝**。最可稽核的 Personal Team 測試方式仍是從原始碼以 Xcode／Flutter 建置；若使用 AltStore、Sideloadly 等第三方重簽工具，需自行確認工具來源，並以自己的 Apple ID／Team 簽章。免費 Personal Team profile 通常 7 天到期，之後必須重新簽章安裝。

要升級為穩定 GitHub Release，至少先完成以下發布門檻：

1. 找回 Android v1.2.2 使用的 keystore，並確認簽章 SHA-256 為 `40f5b5e6ebd8dda1b04f9a4399fac5cc0747cf8af69fe1d77918290955f34cdd`；把 keystore base64 與密碼放入 GitHub Actions secrets，不得提交檔案。
2. 穩定 Release 必須同時附上可覆蓋升級的正式簽章 APK，否則 Android 端會偵測到新版卻無法下載。
3. 若要提供不需使用者自行重簽的 iOS 發布，加入 Apple Developer Program，改用 TestFlight／App Store，或使用包含已登錄裝置的 Ad Hoc distribution profile；Personal Team 不可作為公開通用 IPA。

## 6. iOS smoke test

每次 iOS 平台或相依變更至少確認：

- 首次引導可完成／略過，重開 App 不會再次錯誤顯示。
- 建立、貼上、開啟與另存 Markdown；檔案選擇器取消時不報錯。
- Markdown、程式碼、SVG、LaTeX、圖片縮放與外部連結可用。
- 淺／深色、旋轉、介面大字與閱讀字級不 overflow。
- HackMD 與 GitHub 登入 token 可寫入／讀回 Keychain，登出後確實清除。
- HackMD／GitHub 開啟、離線快取、同步、衝突合併與復原流程。
- AI 自訂端點與內建代理的成功、串流中斷、逾時與取消。
- 發現新版時，iOS 只開啟 GitHub release page，不嘗試下載或安裝 APK。
- App 刪除重裝、背景切回、網路中斷恢復後行為合理。

## 7. 驗證結果紀錄格式

每次測試在 PR 或交付說明記錄：

```text
日期 / macOS / Xcode / Flutter：
目標裝置與 OS：
format / analyze / test：
iOS no-codesign build：
Simulator run：
實機簽章與安裝：
Smoke test：
未驗證項目與原因：
```

建置成功、Simulator 成功與實機側載成功是三個不同層級，必須分開回報。

## 2026-08-12 本機驗證紀錄

環境：macOS 26.5.1、Xcode 26.6、Flutter 3.44.9、Dart 3.12.2、CocoaPods 1.17.0。

| 層級 | 結果 | 證據／限制 |
| --- | --- | --- |
| 格式 | 通過 | 44 個 Dart 檔案，0 個變更 |
| 靜態分析 | 通過 | `flutter analyze` 回報 0 issue |
| 自動測試 | 通過 | 42 tests passed |
| iOS 無簽章 device build | 通過 | 產生 `build/ios/iphoneos/Runner.app` |
| iOS Simulator 安裝／啟動 | 通過 | iPhone 17 Pro / iOS 26.5；App 進入首次引導且沒有 crash |
| iOS 實機側載 | 通過 | iPad Air 11-inch (M2) / iOS 26.6；Personal Team 自動簽章，Debug 安裝／工具啟動通過；Release `Itou Md 1.2.2 (5)` 安裝、獨立啟動且程序持續存活 |

驗證期間補齊 CocoaPods 與 iOS 26.5 Simulator runtime，並完成 iPad 配對、Developer Mode、Xcode Managed Profile 與開發者信任。`open_filex` 的 iOS SPM 支援仍是待追蹤的相依風險；在它支援 SPM 或被移除前，CI 與開發機都必須保留 CocoaPods。
