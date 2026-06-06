#!/usr/bin/env bash
# =============================================================
# rollback.sh — 一键回滚 canary (流量切回 100% stable)
#
# 用法: ./rollback.sh
# =============================================================
set -euo pipefail

NS="myapp"

echo "=== Rolling back canary ==="
echo ""

# 1. 删除 canary ingress (nginx 自动切回 stable)
echo "Step 1: Removing canary ingress..."
kubectl delete ingress myapp-canary -n "$NS" --ignore-not-found || true

# 2. 缩容 canary
echo "Step 2: Scaling down canary deployment..."
kubectl scale deploy myapp-canary -n "$NS" --replicas=0 2>/dev/null || true

# 3. 删除 canary 资源
echo "Step 3: Deleting canary resources..."
kubectl delete deploy myapp-canary -n "$NS" --ignore-not-found || true
kubectl delete svc myapp-canary -n "$NS" --ignore-not-found || true

echo ""
echo "=== Rollback complete! All traffic → stable. ==="
echo ""
kubectl get pods,svc,ingress -n "$NS"
