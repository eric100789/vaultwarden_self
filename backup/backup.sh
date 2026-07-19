#!/usr/bin/env bash
# Vaultwarden 備份腳本：SQLite 線上備份（免停機）→ 打包 → 本機輪替 → (可選) rsync 到 Synology NAS
# 用法：./backup/backup.sh   （建議掛 cron，見 SETUP.md）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONF="$SCRIPT_DIR/backup.conf"
CONTAINER="vaultwarden"
DATA_DIR="$PROJECT_DIR/vw-data"
LOG_FILE="$SCRIPT_DIR/backup.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { log "錯誤：$*"; exit 1; }

[ -f "$CONF" ] || die "找不到 $CONF，請先 cp backup.conf.example backup.conf 並填好設定"
# shellcheck source=/dev/null
source "$CONF"

[ -d "$DATA_DIR" ] || die "找不到資料目錄 $DATA_DIR（Vaultwarden 還沒啟動過？）"

# LOCAL_BACKUP_DIR 允許相對路徑（相對於專案根目錄）
case "$LOCAL_BACKUP_DIR" in
  /*) BACKUP_DIR="$LOCAL_BACKUP_DIR" ;;
  *)  BACKUP_DIR="$PROJECT_DIR/$LOCAL_BACKUP_DIR" ;;
esac
mkdir -p "$BACKUP_DIR"

TS="$(date '+%Y%m%d-%H%M%S')"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

log "===== 開始備份 ====="

# --- 1. SQLite 資料庫備份（保證一致性，不需停機） ---
if docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  # 容器運作中：用 Vaultwarden 內建 backup 指令（SQLite online backup）
  docker exec "$CONTAINER" /vaultwarden backup >/dev/null \
    || die "容器內 /vaultwarden backup 執行失敗"
  DB_BACKUP="$(ls -t "$DATA_DIR"/db_*.sqlite3 2>/dev/null | head -n1)"
  [ -n "$DB_BACKUP" ] || die "找不到 /vaultwarden backup 產生的 db_*.sqlite3"
  cp "$DB_BACKUP" "$STAGING/db.sqlite3"
  rm -f "$DATA_DIR"/db_*.sqlite3   # 清掉留在 data 目錄裡的中間產物
  log "資料庫備份完成（容器內線上備份）"
elif command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DATA_DIR/db.sqlite3" ".backup '$STAGING/db.sqlite3'" \
    || die "host sqlite3 備份失敗"
  log "資料庫備份完成（host sqlite3，容器未運作）"
else
  # 容器沒在跑＝沒有寫入，直接複製是安全的
  cp "$DATA_DIR/db.sqlite3" "$STAGING/db.sqlite3"
  log "資料庫備份完成（直接複製，容器未運作）"
fi

# --- 2. 其他必要檔案 ---
for item in attachments sends config.json; do
  [ -e "$DATA_DIR/$item" ] && cp -r "$DATA_DIR/$item" "$STAGING/"
done
# RSA 金鑰（遺失會讓所有已登入的裝置被登出）
cp "$DATA_DIR"/rsa_key* "$STAGING/" 2>/dev/null || true

# --- 3. 打包 ---
ARCHIVE="$BACKUP_DIR/vaultwarden-$TS.tar.gz"
tar czf "$ARCHIVE" -C "$STAGING" .
log "已打包：$ARCHIVE（$(du -h "$ARCHIVE" | cut -f1)）"

# --- 4. 本機輪替 ---
DELETED=$(find "$BACKUP_DIR" -maxdepth 1 -name 'vaultwarden-*.tar.gz' -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
log "本機輪替：刪除 $DELETED 個超過 $RETENTION_DAYS 天的舊備份"

# --- 5. 上傳 NAS（可開關） ---
if [ "${BACKUP_TO_NAS:-false}" = "true" ]; then
  log "上傳 NAS：$NAS_USER@$NAS_HOST:$NAS_DEST_DIR"
  rsync -az -e "ssh -p $NAS_SSH_PORT -i $SSH_KEY -o BatchMode=yes" \
    "$BACKUP_DIR"/vaultwarden-*.tar.gz \
    "$NAS_USER@$NAS_HOST:$NAS_DEST_DIR/" \
    || die "rsync 上傳 NAS 失敗"
  log "NAS 上傳完成"

  if [ "${NAS_RETENTION_DAYS:-0}" -gt 0 ]; then
    ssh -p "$NAS_SSH_PORT" -i "$SSH_KEY" -o BatchMode=yes "$NAS_USER@$NAS_HOST" \
      "find '$NAS_DEST_DIR' -maxdepth 1 -name 'vaultwarden-*.tar.gz' -mtime +$NAS_RETENTION_DAYS -delete" \
      || log "警告：NAS 端清理舊備份失敗（不影響本次備份）"
    log "NAS 輪替：已清理超過 $NAS_RETENTION_DAYS 天的舊備份"
  fi
else
  log "BACKUP_TO_NAS=false，跳過 NAS 上傳"
fi

log "===== 備份完成 ====="
