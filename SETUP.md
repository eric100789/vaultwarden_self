# Vaultwarden 自架完整指南

架構：Docker Compose 跑 Vaultwarden + Cloudflare Tunnel，備份到本機 + Synology NAS。

```
使用者瀏覽器/APP
      │ https://vault.你的網域.com
      ▼
  Cloudflare（HTTPS 憑證、DDoS 防護）
      │ Tunnel（cloudflared 容器主動向 Cloudflare 建立連線）
      ▼
┌─ 你的 Linux 伺服器 ──────────────────────┐
│  cloudflared ──docker 內網──▶ vaultwarden │
│                                │          │
│                    127.0.0.1:VW_PORT      │
│                   （僅本機除錯用）          │
└──────────────────────────────────────────┘
```

**為什麼不用開 port：** cloudflared 是「從伺服器往外」連到 Cloudflare 的，所以防火牆不用開任何對外 port，也永遠不會跟你其他 docker app 的 port 打架。`VW_PORT` 只綁 `127.0.0.1`，純粹讓你在伺服器上 `curl localhost:8200` 除錯用，要換成任何數字都行。

---

## 1. 事前準備

- [ ] Linux 伺服器，已裝 Docker 與 Docker Compose v2（`docker compose version` 能跑）
- [ ] 網域已加入 Cloudflare（DNS 由 Cloudflare 代管）
- [ ] Gmail 帳號已開啟兩步驟驗證（等下要產生應用程式密碼）
- [ ] Synology NAS 在同網段或可連線（備份用）

把這個 repo 放到伺服器上（例如 `/opt/vaultwarden`）：

```bash
git clone <你的 repo 網址> /opt/vaultwarden
cd /opt/vaultwarden
```

## 2. 建立 Cloudflare Tunnel

1. 開 [Cloudflare Zero Trust 後台](https://one.dash.cloudflare.com/) → **Networks → Tunnels → Create a tunnel**
2. 選 **Cloudflared**，取個名字（例如 `vaultwarden`）
3. 建立後會顯示安裝指令，**只要複製其中的 token**（`eyJ...` 開頭的長字串），這就是 `.env` 裡的 `TUNNEL_TOKEN`。不用照它的指令安裝，我們用 compose 跑。
4. 到 **Public Hostname** 頁籤 → **Add a public hostname**：
   - Subdomain：`vault`（或你喜歡的名字）
   - Domain：選你的網域
   - Service：Type 選 `HTTP`，URL 填 `vaultwarden:80`
     （cloudflared 跟 vaultwarden 在同一個 docker 網路，直接用容器名互連）
5. 存檔。Cloudflare 會自動幫這個子網域建 DNS 記錄與 HTTPS 憑證。

> 建議順手做：Cloudflare DNS 那頁確認該記錄是橘色雲（Proxied）；SSL/TLS 模式用 Full。

## 3. 產生 Gmail 應用程式密碼

1. 到 <https://myaccount.google.com/apppasswords>（需已開兩步驟驗證）
2. 建立一個應用程式密碼，名稱隨意（例如 `vaultwarden`）
3. 記下 16 碼密碼（中間空格不用），填到 `.env` 的 `SMTP_PASSWORD`

## 4. 填寫 .env

```bash
cp .env.example .env
nano .env
```

必填欄位：

| 欄位 | 說明 |
|---|---|
| `DOMAIN` | `https://vault.你的網域.com`（跟 Tunnel 設定的一致，一定要 https 開頭） |
| `VW_PORT` | 本機除錯 port，跟其他服務衝突就換 |
| `TUNNEL_TOKEN` | 步驟 2 拿到的 token |
| `ADMIN_TOKEN` | 見下方 |
| `SMTP_USERNAME` / `SMTP_FROM` | 你的 Gmail |
| `SMTP_PASSWORD` | 步驟 3 的 16 碼應用程式密碼 |

**產生 ADMIN_TOKEN**（admin 後台的密碼，存的是 argon2 雜湊）：

```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
# 輸入你想要的後台密碼兩次，會輸出一行 $argon2id$... 開頭的雜湊
```

把整串雜湊填入 `.env`，**必須用單引號包住**（裡面的 `$` 才不會被 compose 吃掉）：

```
ADMIN_TOKEN='$argon2id$v=19$m=65540,t=3,p=4$xxxx$yyyy'
```

## 5. 啟動與首次登入

```bash
docker compose up -d
docker compose logs -f        # 看到 cloudflared "Registered tunnel connection" 即成功
```

驗收：

1. 瀏覽器開 `https://vault.你的網域.com` → 應出現 Vaultwarden 登入頁
2. 開 `https://vault.你的網域.com/admin` → 輸入你在步驟 4 設的後台密碼
3. admin 後台 → **SMTP Email Settings** 最下面 **Send test email** → 收得到信即 SMTP 正常
4. 建立你自己的帳號：因為預設關閉註冊，請從 admin 後台 **Users → Invite User** 寄邀請給自己的信箱，點信裡連結完成註冊

手機 APP / 瀏覽器擴充功能登入時，在登入畫面選「自架伺服器」填 `https://vault.你的網域.com` 即可。

## 6. 分享給別人（註冊開關）

**建議做法 — 邀請制（不用開放註冊）：**
admin 後台 → Users → Invite User → 填對方 Email → 對方收信點連結註冊。全程 `SIGNUPS_ALLOWED` 保持 `false`，陌生人永遠無法註冊。

**臨時開放註冊**（例如想讓對方自己來註冊）：

- 方法 A（改設定檔，明確可控）：`.env` 改 `SIGNUPS_ALLOWED=true` → `docker compose up -d` → 對方註冊完 → 改回 `false` → 再 `docker compose up -d`
- 方法 B（admin 後台）：General settings → 勾/取消 **Allow new signups** → Save。注意：後台儲存過的設定會寫進 `config.json` 並**蓋過 .env 的值**，之後想改就都從後台改，或刪掉 `vw-data/config.json` 回歸 .env。

建議固定用其中一種方法就好，避免搞不清楚哪邊的設定生效。

## 7. 備份設定

### 7.1 NAS 端（DSM）一次性設定

1. **建備份帳號**：控制台 → 使用者帳號 → 新增 `vwbackup`（一般使用者即可）
2. **開 SSH**：控制台 → 終端機 & SNMP → 勾「啟動 SSH 功能」（記下 port）
3. **開 rsync**：控制台 → 檔案服務 → rsync → 勾「啟動 rsync 服務」
4. **建共享資料夾**：例如 `backup`，給 `vwbackup` 讀寫權限；備份會放在 `/volume1/backup/vaultwarden`
5. **允許 SSH 金鑰登入**（DSM 預設一般使用者不能用金鑰，需開啟家目錄服務）：控制台 → 使用者帳號 → 進階設定 → 勾「啟用家目錄服務」

在**伺服器**上產生金鑰並複製到 NAS：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""   # 已有金鑰可跳過
ssh-copy-id -p 22 vwbackup@<NAS_IP>                 # 輸入一次 vwbackup 密碼
ssh -p 22 vwbackup@<NAS_IP> 'echo ok'               # 測試：不問密碼直接印 ok 即成功
ssh -p 22 vwbackup@<NAS_IP> 'mkdir -p /volume1/backup/vaultwarden'
```

> 若 ssh-copy-id 後還是要密碼：SSH 進 NAS 執行 `chmod 755 ~; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys`（DSM 家目錄權限太寬會被 sshd 拒絕）。

### 7.2 伺服器端設定

```bash
cd /opt/vaultwarden
cp backup/backup.conf.example backup/backup.conf
nano backup/backup.conf        # 填 NAS_HOST、NAS_USER、NAS_DEST_DIR 等
chmod +x backup/backup.sh backup/restore.sh
```

**NAS 上傳開關**：`backup.conf` 裡的 `BACKUP_TO_NAS=true/false`，隨時改，下次備份生效，不用重啟任何東西。

手動測試一次：

```bash
./backup/backup.sh
# 確認：backups/ 出現 vaultwarden-*.tar.gz，NAS 目的資料夾也出現同名檔案
```

### 7.3 排程（每天 03:00）

```bash
crontab -e
# 加入這行（路徑照你的實際位置改）：
0 3 * * * /opt/vaultwarden/backup/backup.sh >> /opt/vaultwarden/backup/cron.log 2>&1
```

備份內容：資料庫（SQLite 線上備份，免停機）、附件、Send、RSA 金鑰、config.json。log 在 `backup/backup.log`。

## 8. 還原（請至少演練一次！）

```bash
./backup/restore.sh backups/vaultwarden-20260719-030000.tar.gz
# 不帶參數執行會列出可用的備份檔
```

腳本會：停容器 → 把現有 `vw-data/` 改名保留 → 解壓備份 → 重啟。確認一切正常後再手動刪除舊目錄。

**災難復原**（伺服器整台掛掉，換新機器）：

1. 新機器裝好 Docker，`git clone` 這個 repo
2. 從 NAS 抓最新備份：`scp -P 22 vwbackup@<NAS_IP>:/volume1/backup/vaultwarden/vaultwarden-最新.tar.gz backups/`
3. 重建 `.env`（`TUNNEL_TOKEN`、`ADMIN_TOKEN` 等；Tunnel token 在 Cloudflare 後台可重新查看）
4. `mkdir -p vw-data && tar xzf backups/vaultwarden-最新.tar.gz -C vw-data && docker compose up -d`

> `.env` 和 `backup/backup.conf` 不在備份檔裡（它們在 git 之外、含機密）。建議把這兩個檔案的內容另外抄進你自己的密碼庫或安全的地方。

## 9. 日常維護

**更新 Vaultwarden**（建議每一兩個月）：

```bash
cd /opt/vaultwarden
./backup/backup.sh                 # 更新前先備份
docker compose pull
docker compose up -d
docker image prune -f
```

**看 log**：`docker compose logs -f vaultwarden`

**常見問題**：

| 症狀 | 檢查 |
|---|---|
| 網址打不開 | `docker compose logs cloudflared` 有沒有 `Registered tunnel connection`；token 是否貼錯 |
| 收不到邀請信 | admin 後台 Send test email；Gmail 應用程式密碼是否失效（改 Google 密碼會全部撤銷） |
| /admin 進不去 | `ADMIN_TOKEN` 是否用單引號包住整串雜湊 |
| 改了 .env 沒生效 | 要 `docker compose up -d` 才會套用；另外檢查是否被 `vw-data/config.json`（admin 後台存過的設定）蓋掉 |
| 備份失敗 | 看 `backup/backup.log`；NAS 連線問題先測 `ssh -p <port> -i <key> vwbackup@<NAS_IP> 'echo ok'` |
