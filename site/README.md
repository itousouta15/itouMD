# itouMD 官網

`md.itousouta.me` 的靜態站台，部署在 Cloudflare Workers（Static Assets）。

```
site/
├── wrangler.toml          Worker 設定（自訂網域、資產目錄）
└── public/                實際上線的檔案
    ├── index.html         整站就這一頁（CSS／JS 內嵌）
    ├── logo.webp          由 assets/logo/logo_nbg.webp 複製而來
    ├── _headers           快取與安全標頭
    └── screenshots/       實機截圖（README 也引用同一份）
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
換截圖的話覆蓋 `public/screenshots/` 底下同名檔案即可，根目錄的 README 引用的是同一份。
