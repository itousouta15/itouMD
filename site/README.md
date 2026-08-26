# itouMD 官網

`md.itousouta.me` 的靜態站台，部署在 Cloudflare Workers（Static Assets）。

```
site/
├── wrangler.toml          Worker 設定（自訂網域、資產目錄）
└── public/                實際上線的檔案
    ├── index.html         整站就這一頁（CSS／JS 內嵌）
    ├── logo.webp          由 assets/logo/logo_nbg.webp 複製而來
    ├── _headers           快取與安全標頭
    └── screenshots/       實機截圖（*.png 由根目錄 README 引用，*.webp 給站台）
```

## 本機預覽

```bash
cd site
npx wrangler dev
```

## 部署

```bash
cd site
npx wrangler deploy
```

需要先 `npx wrangler login`，且 Cloudflare 帳號底下要有 `itousouta.me` 這個 zone——
自訂網域的 DNS 紀錄由 wrangler 自動建立。若 zone 還沒轉入，先把 `wrangler.toml`
裡的 `routes` 註解掉，站台會落在 `itoumd-site.<subdomain>.workers.dev`。

## 改內容

`public/index.html` 是唯一的來源檔，沒有建置步驟——直接改、直接部署。

## 換截圖

覆蓋 `public/screenshots/` 底下的同名 `.png`（根目錄的 README 引用的就是這幾份），
**接著要重產 `.webp`**——站台上的 `<picture>` 優先吃 WebP，只留 PNG 會看到舊畫面：

```bash
cd site/public/screenshots
npx sharp-cli -i "*.png" -o . resize 900 --withoutEnlargement -- --format webp --quality 76
```

900px 寬是照網頁上最寬的顯示尺寸（290 CSS px）抓 3 倍算的，六張加起來約 240 KB，
PNG 原檔約 1 MB——手機上差很多，所以別省這一步。
