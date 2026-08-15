#!/usr/bin/env sh
# 給 docker-compose 的 backup 服務用：容器啟動（docker compose up）時立刻備份
# 一次，之後每隔 BACKUP_INTERVAL_SECONDS 秒再備份一次。輪替/刪舊備份的邏輯都在
# backup.sh 裡，這支腳本只負責「立刻跑一次 + 定時重跑」。
set -eu

apk add --no-cache bash rsync openssh-client tzdata >/dev/null

INTERVAL="${BACKUP_INTERVAL_SECONDS:-86400}"
SCRIPT="$(dirname "$0")/backup.sh"

echo "[backup-loop] 啟動，備份間隔 ${INTERVAL} 秒"

while true; do
  bash "$SCRIPT" || echo "[backup-loop] 本次備份失敗，等下次重試"
  sleep "$INTERVAL"
done
