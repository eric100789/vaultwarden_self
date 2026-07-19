#!/usr/bin/env bash
# Vaultwarden 還原腳本：從 backup.sh 產生的 tar.gz 還原整個 data 目錄
# 用法：./backup/restore.sh backups/vaultwarden-20260719-030000.tar.gz
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/vw-data"

if [ $# -ne 1 ]; then
  echo "用法：$0 <備份檔.tar.gz>"
  echo "可用的備份："
  ls -1t "$PROJECT_DIR"/backups/vaultwarden-*.tar.gz 2>/dev/null || echo "  （backups/ 裡沒有備份檔）"
  exit 1
fi

ARCHIVE="$1"
[ -f "$ARCHIVE" ] || { echo "錯誤：找不到 $ARCHIVE"; exit 1; }

# 先驗證壓縮檔完整、內容看起來像 Vaultwarden 備份
tar tzf "$ARCHIVE" >/dev/null || { echo "錯誤：$ARCHIVE 不是有效的 tar.gz"; exit 1; }
tar tzf "$ARCHIVE" | grep -q 'db.sqlite3' || { echo "錯誤：$ARCHIVE 裡沒有 db.sqlite3，不像是本專案的備份檔"; exit 1; }

echo "即將用 $ARCHIVE 覆蓋現有的 Vaultwarden 資料。"
echo "現有資料會先改名保留（不會直接刪除）。"
read -r -p "確定要還原嗎？(yes/no) " ANSWER
[ "$ANSWER" = "yes" ] || { echo "已取消"; exit 0; }

cd "$PROJECT_DIR"

echo "[1/4] 停止 Vaultwarden..."
docker compose stop vaultwarden

if [ -d "$DATA_DIR" ]; then
  KEEP="$DATA_DIR.old-$(date '+%Y%m%d-%H%M%S')"
  echo "[2/4] 保留現有資料到 $KEEP"
  mv "$DATA_DIR" "$KEEP"
else
  echo "[2/4] 沒有現有資料目錄，跳過保留"
fi

echo "[3/4] 解壓備份..."
mkdir -p "$DATA_DIR"
tar xzf "$ARCHIVE" -C "$DATA_DIR"

echo "[4/4] 重新啟動..."
docker compose up -d

echo ""
echo "還原完成。請驗證："
echo "  1. 瀏覽器開啟你的網域，登入帳號確認密碼庫內容正確"
echo "  2. docker compose logs -f vaultwarden 確認沒有錯誤"
echo "  3. 確認一切正常後，可手動刪除舊資料：rm -rf ${KEEP:-（無）}"
