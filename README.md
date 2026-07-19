# Vaultwarden Self-Hosted

自架 Vaultwarden 密碼管理伺服器：Docker Compose + Cloudflare Tunnel（免開 port）+ Gmail SMTP + 本機/Synology NAS 備份。

**完整安裝與維運指南：[SETUP.md](SETUP.md)**

## 檔案結構

```
docker-compose.yml           # vaultwarden + cloudflared
.env.example                 # 環境變數範本（複製成 .env 填入機密）
backup/backup.sh             # 備份：免停機 DB 備份 → 打包 → 輪替 → (可開關) rsync 到 NAS
backup/restore.sh            # 還原：從備份檔一鍵還原
backup/backup.conf.example   # 備份設定範本（複製成 backup.conf）
SETUP.md                     # 完整指南
```

## 快速開始

```bash
cp .env.example .env && nano .env                            # 照 SETUP.md 填
cp backup/backup.conf.example backup/backup.conf             # 備份設定
chmod +x backup/*.sh
docker compose up -d
```
