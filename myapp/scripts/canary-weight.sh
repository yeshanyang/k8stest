#!/usr/bin/env bash
# =============================================================
# canary-weight.sh — 调整灰度流量权重
#
# 用法: ./canary-weight.sh <0-100>
# 示例: ./canary-weight.sh 10   # 10% 流量到 canary
# =============================================================
set -euo pipefail

WEIGHT=${1:-0}

if [[ "$WEIGHT" -lt 0 || "$WEIGHT" -gt 100 ]]; then
    echo "Error: weight must be 0-100"
    exit 1
fi

NS="myapp"
INGRESS_NAME="myapp-canary"

echo "Setting canary weight to ${WEIGHT}%"

kubectl annotate ingress "$INGRESS_NAME" \
    -n "$NS" \
    --overwrite \
    nginx.ingress.kubernetes.io/canary-weight="$WEIGHT"

echo "Done. Canary now receives ${WEIGHT}% traffic."
echo ""
echo "Verify traffic split:"
echo "  for i in {1..10}; do curl -sH 'Host: myapp.3hang.asia' http://<node-ip> | grep version; done"
