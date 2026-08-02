# 貢獻指南

謝謝你願意花時間貢獻 itouMD！這份文件說明回報問題、提出功能、送出 PR 的流程與規範。
參與本專案前，請先閱讀 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)。

## 開發環境設置

完整的環境需求、取得原始碼、安裝依賴、執行 App 的步驟請參考
[`README.md`](README.md#啟動完整流程)。

Windows 開發者請特別注意：專案路徑必須是純 ASCII，詳見 [`DEV_NOTES.md`](DEV_NOTES.md)。

## 回報 Bug

回報前請先：

1. 確認使用的是最新版本（`git pull` / 最新 Release）。
2. 在 [Issues](https://github.com/itousouta15/itouMD/issues) 搜尋是否已有相同回報。

確認後請用 **Bug report** Issue 範本開一則新 Issue，並盡量附上：

- 重現步驟（含用到的 Markdown 原始碼或網址，若方便提供的話）
- 預期行為與實際行為
- 裝置型號、作業系統版本、App 版本
- 螢幕截圖或錄影（如果是畫面顯示問題）

## 提出功能建議

用 **Feature request** Issue 範本描述：

- 想解決的問題或使用情境
- 建議的解法（如果已經有想法）
- 是否願意自己送 PR 實作

## 送出 Pull Request

1. Fork 本專案，開一個新分支（例如 `fix/xxx`、`feat/xxx`）。
2. 進行修改。程式碼風格請遵守專案既有慣例：
   - 沒有特別理由的話，不要新增註解——好的命名比註解更重要；只有在解釋「為什麼」而
     非「做了什麼」時才需要註解。
   - 不要引入超出這次修改範圍的重構或抽象。
   - 避免加入用不到的相依套件、feature flag 或相容性 shim。
3. 送出 PR 前，請在本機跑過以下三個指令，這也是 CI（`.github/workflows/ci.yml`）會
   檢查的項目：

   ```bash
   dart format --output=none --set-exit-if-changed .
   flutter analyze
   flutter test
   ```

   如果 `dart format` 回報有檔案需要調整，直接執行 `dart format .` 套用格式即可。

4. Commit message 請簡短說明「為什麼」而非「做了什麼」（例如 `fix: 修正 HackMD
   spoiler 巢狀時提早截斷的問題`，而不是 `修改 hackmd_syntax.dart`）。
5. 開 PR 時請用 PR 範本，簡述變更內容與測試方式；如果修改會影響畫面呈現，請附上
   截圖或錄影。
6. PR 需要通過 CI 檢查（格式、靜態分析、測試），並經過至少一位維護者 review 後才會
   合併。

## 沒有把握該怎麼做？

歡迎先開一個 Issue 討論，或在既有 Issue 底下留言，維護者會盡量給回饋再開始動工，
避免白工。
