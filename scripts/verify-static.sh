#!/usr/bin/env bash
set -euo pipefail
DIR="${1:-out/bin}"
fail=0
for f in lpmake lpdump lpflash lpadd lpunpack; do
  p="$DIR/$f"
  echo "===== $f ====="
  test -f "$p" || { echo "MISSING"; fail=1; continue; }
  file "$p"
  if readelf -d "$p" | grep -q 'NEEDED'; then
    echo "ERROR: dynamic dependency found"
    readelf -d "$p"
    fail=1
  else
    echo "OK: no DT_NEEDED"
  fi
  readelf -h "$p" | grep -E 'Class:|Machine:|Type:'
done
exit "$fail"
