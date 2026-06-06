#!/usr/bin/env bash
# =============================================================
# promote.sh — 将 canary 提升为 stable (全量发布)
#
# 流程:
#   1. 将 canary 权重调到 100%
#   2. 等待验证
#   3. 确认后将 stable Deployment 更新为 canary 的镜像
#   4. 删除 canary 资源和 Ingress 规则
# =============================================================
set -euo pipefail

NS="myapp"

echo "=== Step 1: Route 100% traffic to canary ==="
kubectl annotate ingress myapp-canary \
    -n "$NS" \
    --overwrite \
    nginx.ingress.kubernetes.io/canary-weight=100

echo ""
echo "=== Step 2: Verify canary is healthy ==="
echo "  kubectl get pods -n $NS -l track=canary"
echo "  curl -H 'Host: myapp.3hang.asia' http://<node-ip>"

echo ""
echo -n "Press Enter to promote canary to stable (Ctrl+C to abort): "
read -r

echo ""
echo "=== Step 3: Update stable to canary's image ==="
# 获取 canary 的镜像 tag
CANARY_IMAGE=$(kubectl get deploy myapp-canary -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Canary image: $CANARY_IMAGE"

kubectl set image deploy/myapp -n "$NS" "myapp=$CANARY_IMAGE"

echo ""
echo "=== Step 4: Delete canary resources ==="
kubectl delete ingress myapp-canary -n "$NS" --ignore-not-found
kubectl delete deploy myapp-canary -n "$NS" --ignore-not-found
kubectl delete svc myapp-canary -n "$NS" --ignore-not-found

echo ""
echo "=== Done! Stable is now serving the new version. ==="
kubectl get pods -n "$NS"
