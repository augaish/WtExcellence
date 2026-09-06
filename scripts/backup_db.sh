#!/usr/bin/env bash
# Dump the wtexcel production database to /root/backups on the server.
#
#   bash scripts/backup_db.sh [label]
#
# Restore:
#   gunzip -c /root/backups/<file>.sql.gz | docker exec -i wtexcel-db psql -U postgres -d way_to_excellence
set -euo pipefail

LABEL="${1:-manual}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR=/root/backups
OUT="${OUT_DIR}/wtexcel_${LABEL}_${STAMP}.sql.gz"

mkdir -p "$OUT_DIR"

DB_CONTAINER="$(docker ps --filter 'name=wtexcel-db' --format '{{.Names}}' | head -1)"
if [ -z "$DB_CONTAINER" ]; then
  echo "ERROR: wtexcel-db container not running" >&2
  exit 1
fi

echo "Dumping from ${DB_CONTAINER} -> ${OUT}"
docker exec "$DB_CONTAINER" pg_dump -U postgres way_to_excellence | gzip > "$OUT"

echo "Done: $(ls -lh "$OUT" | awk '{print $5}') at ${OUT}"
ls -1t "${OUT_DIR}"/wtexcel_*.sql.gz | tail -n +11 | xargs -r rm -f
echo "Kept the 10 most recent backups."
