#!/usr/bin/env bash
# Dump the wtexcel production database to /root/backups on the server.
#
#   bash scripts/backup_db.sh [label]
#
# Restore:
#   gunzip -c /root/backups/<file>.sql.gz | docker exec -i wtexcel-db psql -U postgres -d way_to_excellence
#
# This script verifies its own output. An earlier version wrote a 20-byte empty
# archive and printed "Done", which is the worst way for a backup to fail: it
# looks like protection right up until the moment it is needed. Every step is
# now checked, and the script exits non-zero rather than leaving a file behind
# that cannot be restored.
set -euo pipefail

LABEL="${1:-manual}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR=/root/backups
OUT="${OUT_DIR}/wtexcel_${LABEL}_${STAMP}.sql.gz"

# A dump smaller than this cannot contain a real schema.
MIN_BYTES=10240

mkdir -p "$OUT_DIR"

fail() { echo "BACKUP FAILED: $*" >&2; rm -f "$OUT"; exit 1; }

DB_CONTAINER="$(docker ps --filter 'name=wtexcel-db' --format '{{.Names}}' | head -1)"
[ -n "$DB_CONTAINER" ] || fail "no running wtexcel-db container"

# pg_dump inside the container needs the password the container itself was
# started with; without it the dump fails and produces an empty stream.
DB_PASSWORD="$(docker exec "$DB_CONTAINER" printenv POSTGRES_PASSWORD 2>/dev/null || true)"
DB_USER="$(docker exec "$DB_CONTAINER" printenv POSTGRES_USER 2>/dev/null || echo postgres)"
DB_NAME="$(docker exec "$DB_CONTAINER" printenv POSTGRES_DB 2>/dev/null || echo way_to_excellence)"

echo "Container: ${DB_CONTAINER}  user: ${DB_USER}  database: ${DB_NAME}"

# Confirm the database is reachable and actually has tables before dumping, so a
# connection or naming problem is reported as itself rather than as an empty file.
TABLE_COUNT="$(docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
  psql -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>&1)" \
  || fail "cannot query ${DB_NAME}: ${TABLE_COUNT}"

case "$TABLE_COUNT" in
  ''|*[!0-9]*) fail "unexpected reply when counting tables: ${TABLE_COUNT}" ;;
esac
[ "$TABLE_COUNT" -gt 0 ] || fail "${DB_NAME} reports 0 tables — wrong database?"
echo "Tables in ${DB_NAME}: ${TABLE_COUNT}"

echo "Dumping ${DB_NAME} -> ${OUT}"
docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
  pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$OUT" \
  || fail "pg_dump exited non-zero"

# Verify the archive rather than trusting that it was written.
SIZE="$(stat -c%s "$OUT")"
[ "$SIZE" -ge "$MIN_BYTES" ] || fail "archive is only ${SIZE} bytes — the dump is empty or truncated"

gzip -t "$OUT" || fail "archive is not a valid gzip stream"

# A real dump ends with the marker pg_dump writes when it completes; a stream cut
# short does not, which is how a truncated backup is caught.
gunzip -c "$OUT" | tail -5 | grep -q "PostgreSQL database dump complete" \
  || fail "archive does not end with pg_dump's completion marker — it is truncated"

RESTORED_TABLES="$(gunzip -c "$OUT" | grep -c '^CREATE TABLE' || true)"
[ "$RESTORED_TABLES" -gt 0 ] || fail "archive contains no CREATE TABLE statements"

echo "Verified: $(ls -lh "$OUT" | awk '{print $5}'), ${RESTORED_TABLES} tables, gzip intact."
echo "Backup: ${OUT}"

ls -1t "${OUT_DIR}"/wtexcel_*.sql.gz | tail -n +11 | xargs -r rm -f
echo "Kept the 10 most recent backups."
