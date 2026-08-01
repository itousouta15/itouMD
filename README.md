<img src="LOGO.png" width="90" height="90">
<h1>itouMD</h1>

一款用於行動裝置的現代化 Markdown 檢視器，支援本機檔案、貼上內容、遠端 URL 擷取、LaTeX 數學公式與閱讀偏好設定。

## 功能亮點

- **Markdown 渲染**：支援 GitHub Flavored Markdown (GFM) 以及一般常見標記語法。
- **貼上文字檢視**：直接貼上 Markdown 原始碼後即時檢視。
- **本機檔案開啟**：支援 `.md`、`.markdown`、`.mdx`、`.txt` 檔案匯入。
- **網址抓取**：可從 GitHub、Gist、HackMD 等常見 Markdown 網址擷取內容並顯示。
- **LaTeX 數學公式**：支援 inline `$...$` 與 display `$$...$$` 公式展示。
- **閱讀偏好**：可調整字體、字級、文字顏色，並保存設定。
- **主題切換**：支援深色 / 淺色模式切換。
- **最近紀錄**：儲存最近閱讀的 Markdown，方便快速回到先前內容。
- **複製原始 Markdown**：在檢視頁面可快速複製原始內容。

## 目標使用情境

- 想在手機上快速預覽 Markdown 並保留閱讀設定。
- 需要直接瀏覽 GitHub、Gist、HackMD 上的 Markdown 原始內容。
- 需要顯示 LaTeX 數學公式與語法高亮效果。
- 想把本機 Markdown 檔案當成輕量閱讀器使用。

## 專案架構

- `lib/main.dart`：應用入口，負責主題與首頁初始化。
- `lib/screens/home_screen.dart`：首頁 UI，包含貼上、選檔、網址抓取與最近紀錄。
- `lib/screens/viewer_screen.dart`：Markdown 檢視頁面，處理 HTML 轉換、公式渲染與閱讀設定。
- `lib/services/markdown_source.dart`：負責遠端 Markdown 擷取與 URL 正規化。
- `lib/services/recent_docs.dart`：儲存與管理最近閱讀紀錄。
- `lib/services/reader_prefs.dart`：保存讀者偏好設定。
- `lib/services/hackmd_syntax.dart`：擴充 HackMD 容器語法處理。
- `lib/services/latex_preprocessor.dart`：保護 LaTeX 公式避免被 Markdown 解析破壞。
- `lib/theme.dart`：自訂應用主題與顏色樣式。

## 安裝與執行

1. 安裝 Flutter 開發環境，詳見 Flutter 官方文件。
2. 開啟專案資料夾：
   ```bash
   cd itouMD
   ```
3. 取得相依套件：
   ```bash
   flutter pub get
   ```
4. 執行應用：
   ```bash
   flutter run
   ```

## 支援的依賴套件

- `flutter`
- `cupertino_icons`
- `markdown`
- `http`
- `file_picker`
- `google_fonts`
- `shared_preferences`
- `url_launcher`
- `flutter_widget_from_html_core`
- `flutter_math_fork`
- `fwfh_svg`
- `flutter_svg`

## 使用說明

1. 打開 App 後，可直接在「貼上文字」區域輸入或貼上 Markdown。
2. 若要載入本機檔案，點選「選擇 .md 檔案」。
3. 若要載入遠端檔案，貼入 Markdown URL，支援 GitHub blob、Gist、HackMD 連結。
4. 點選「從網址抓取」即可下載並閱讀遠端內容。
5. 點選已讀取內容後，可在檢視頁面使用「顯示設定」調整字體、字級與文字顏色。
6. 在檢視頁面上方可點擊複製按鈕，將原始 Markdown 內容複製到剪貼簿。

## 開發備註

- 遠端 URL 擷取會自動嘗試將常見 GitHub/Gist/HackMD 連結轉換為 raw/下載格式。
- 最近閱讀紀錄儲存在 `SharedPreferences`，最多保存 15 筆。
- LaTeX 公式會先經過預處理，避免 `$` 與 `_` 等符號被 Markdown 解析錯誤。

## 未來可加強項目

- 增加本機檔案資料夾瀏覽器與多檔案選擇。
- 支援更多 Markdown 擴充語法與語法高亮。
- 改善 URL 解析邊界與更多雲端來源的適配。

## 授權

此專案目前未指定授權。若要分享或發布，請依作者需求補上 LICENSE。
