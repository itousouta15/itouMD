# 安全政策

## 支援版本

itouMD 是持續開發中的行動應用程式，只有 **最新發布版本**（[GitHub Releases](https://github.com/itousouta15/itouMD/releases/latest) 上最新的一個 tag）會收到安全性修補。舊版本請自行更新到最新版。

| 版本 | 是否支援 |
| --- | --- |
| 最新 Release | ✅ |
| 較舊版本 | ❌ |

## 回報安全性問題

**請不要透過公開 Issue 回報安全性漏洞**，避免在修補完成前被惡意利用。

請擇一使用以下私下管道回報：

1. 透過本 repo 的 [Security 頁籤](https://github.com/itousouta15/itouMD/security/advisories/new) 建立 Private Vulnerability Report（建議方式，GitHub 會通知維護者且不會公開）。
2. 寄信到 **hi@itousouta.me**，主旨請包含 `[itouMD Security]`。

回報時請盡量提供：

- 問題描述與可能造成的影響
- 重現步驟或概念驗證（PoC）
- 受影響的版本/平台（Android、iOS）

### 回應時間

- 會在 **3 個工作天內** 回覆確認收到回報。
- 會視嚴重程度評估修補時程，並在修補釋出前與回報者保持聯繫。
- 修補釋出後，會在該次 Release 的說明中致謝回報者（除非回報者希望匿名）。

## 涵蓋範圍

以下屬於本專案關注的安全範疇：

- App 本身的邏輯錯誤導致的資料外洩、任意程式碼執行、權限提升等問題
- HackMD API Token 的儲存與傳輸方式（目前使用 Android Keystore / iOS Keychain，透過
  `flutter_secure_storage` 存放）
- 遠端內容擷取（GitHub / Gist / HackMD URL）過程中的注入或 SSRF 類問題
- Markdown／HTML 渲染管線中可能導致的 XSS 或惡意內容執行問題

以下**不**屬於本專案範疇，請直接回報給對應單位：

- HackMD 平台本身或其 API 的安全性問題，請回報給 HackMD
- Flutter / Dart SDK 或第三方套件本身的安全性問題，請回報給對應的上游專案

## 揭露政策

我們採用協調式揭露（coordinated disclosure）：在修補釋出並有合理時間讓使用者更新前，
請勿公開揭露漏洞細節。目前本專案沒有提供漏洞獎金（bug bounty）。
