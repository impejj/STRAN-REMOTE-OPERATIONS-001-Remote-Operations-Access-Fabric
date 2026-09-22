#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-/srv/scientiam/backups/meshcentral}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
TARGET="$OUT/meshcentral-$STAMP.tar.gz"

docker run --rm   -v meshcentral-data:/data:ro   -v meshcentral-files:/files:ro   -v meshcentral-backups:/backups:ro   -v "$OUT:/out"   alpine:3.22 sh -lc "tar -czf /out/$(basename "$TARGET") /data /files /backups"

sha256sum "$TARGET" > "$TARGET.sha256"
echo "BACKUP=$TARGET"
echo "SHA256=$(cut -d' ' -f1 "$TARGET.sha256")"
