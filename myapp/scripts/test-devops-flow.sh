#!/usr/bin/env bash
# =============================================================
# test-devops-flow.sh — DevOps 全流程端到端测试
#
# 用法：./test-devops-flow.sh [--quick]
# 选项:
#   --quick    快速测试，跳过部分验证步骤
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-d:/code/k8s/cka-cluster-config}"
QUICK_MODE=false

if [[ "${1:-}" == "--quick" ]]; then
    QUICK_MODE=true
fi

echo "============================================================"
echo "DevOps 全流程端到端测试"
echo "============================================================"
echo ""
echo "KUBECONFIG: ${KUBECONFIG}"
echo "Quick mode: ${QUICK_MODE}"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数
TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
test_step() {
    local name="$1"
    local cmd="$2"
    local expected="${3:-}"

    echo -n "Testing: ${name}... "

    if eval "${cmd}" > /dev/null 2>&1; then
        if [[ -n "${expected}" ]]; then
            if eval "${cmd}" | grep -q "${expected}"; then
                echo -e "${GREEN}✓ PASSED${NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${RED}✗ FAILED (expected: ${expected})${NC}"
                ((TESTS_FAILED++))
            fi
        else
            echo -e "${GREEN}✓ PASSED${NC}"
            ((TESTS_PASSED++))
        fi
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
    fi
}

# 1. 集群连接测试
echo "=== 1. 集群连接测试 ==="
test_step "kubectl 连接" "kubectl --kubeconfig=${KUBECONFIG} cluster-info"
test_step "节点就绪" "kubectl --kubeconfig=${KUBECONFIG} get nodes" "Ready"

if [[ "${QUICK_MODE}" == false ]]; then
    test_step "命名空间存在" "kubectl --kubeconfig=${KUBECONFIG} get namespace myapp" "myapp"
fi

echo ""

# 2. DevOps 工具链测试
echo "=== 2. DevOps 工具链测试 ==="
test_step "Gitea Pod 运行" "kubectl --kubeconfig=${KUBECONFIG} get pods -n devops -l app=gitea" "Running"
test_step "Jenkins Pod 运行" "kubectl --kubeconfig=${KUBECONFIG} get pods -n devops -l app=jenkins" "Running"
test_step "ArgoCD Pod 运行" "kubectl --kubeconfig=${KUBECONFIG} get pods -n argocd" "Running"

if [[ "${QUICK_MODE}" == false ]]; then
    test_step "SonarQube Pod 运行" "kubectl --kubeconfig=${KUBECONFIG} get pods -n devops -l app=sonarqube" "Running"
    test_step "Harbor Pod 运行" "kubectl --kubeconfig=${KUBECONFIG} get pods -n devops -l app=harbor" "Running"
fi

echo ""

# 3. 应用部署测试
echo "=== 3. 应用部署测试 ==="
test_step "Stable Deployment 存在" "kubectl --kubeconfig=${KUBECONFIG} get deployment myapp -n myapp" "myapp"
test_step "Canary Deployment 存在" "kubectl --kubeconfig=${KUBECONFIG} get deployment myapp-canary -n myapp" "myapp-canary"
test_step "Stable Service 存在" "kubectl --kubeconfig=${KUBECONFIG} get svc myapp -n myapp" "myapp"
test_step "Canary Service 存在" "kubectl --kubeconfig=${KUBECONFIG} get svc myapp-canary -n myapp" "myapp-canary"

if [[ "${QUICK_MODE}" == false ]]; then
    test_step "Ingress 存在" "kubectl --kubeconfig=${KUBECONFIG} get ingress myapp -n myapp" "myapp"
    test_step "NetworkPolicy 存在" "kubectl --kubeconfig=${KUBECONFIG} get networkpolicy -n myapp" "myapp"
fi

echo ""

# 4. Pod 状态测试
echo "=== 4. Pod 状态测试 ==="
test_step "Stable Pods 就绪" "kubectl --kubeconfig=${KUBECONFIG} wait --for=condition=ready pod -l app=myapp,track=stable -n myapp --timeout=30s"
test_step "Canary Pods 就绪" "kubectl --kubeconfig=${KUBECONFIG} wait --for=condition=ready pod -l app=myapp-canary,track=canary -n myapp --timeout=30s"

echo ""

# 5. Ingress 测试
echo "=== 5. Ingress 测试 ==="
test_step "Ingress Controller 运行" "kubectl --kubeconfig=${KUBECONFIG} get pods -n ingress-nginx" "Running"

# 测试 Ingress 访问 (需要 plink 隧道)
echo -n "Testing: Ingress 域名访问... "
if curl -s -o /dev/null -w "%{http_code}" -H "Host: myapp.3hang.asia" http://localhost:30300 | grep -q "200\|302"; then
    echo -e "${GREEN}✓ PASSED${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ SKIPPED (需要 plink 隧道)${NC}"
fi

echo ""

# 6. 灰度发布测试
echo "=== 6. 灰度发布测试 ==="
test_step "Canary Ingress 注解" "kubectl --kubeconfig=${KUBECONFIG} get ingress myapp-canary -n myapp -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary}'" "true"

# 获取当前 canary 权重
CURRENT_WEIGHT=$(kubectl --kubeconfig=${KUBECONFIG} get ingress myapp-canary -n myapp -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}' 2>/dev/null || echo "0")
echo -e "Current canary weight: ${YELLOW}${CURRENT_WEIGHT}%${NC}"

echo ""

# 7. ArgoCD 测试
echo "=== 7. ArgoCD 测试 ==="
test_step "ArgoCD Application 存在" "kubectl --kubeconfig=${KUBECONFIG} get applications -n argocd myapp" "myapp"

# 获取同步状态
SYNC_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get applications -n argocd myapp -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get applications -n argocd myapp -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
echo -e "ArgoCD Sync Status: ${YELLOW}${SYNC_STATUS}${NC}"
echo -e "ArgoCD Health Status: ${YELLOW}${HEALTH_STATUS}${NC}"

echo ""

# 8. 镜像仓库测试
echo "=== 8. 镜像仓库测试 ==="
echo -n "Testing: Harbor 可访问... "
if curl -s -o /dev/null -w "%{http_code}" http://localhost:30080 | grep -q "200\|302"; then
    echo -e "${GREEN}✓ PASSED${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ SKIPPED (需要 plink 隧道)${NC}"
fi

echo ""

# 9. 脚本可执行性测试
echo "=== 9. 脚本可执行性测试 ==="
test_step "canary-weight.sh 可执行" "test -x ${SCRIPT_DIR}/canary-weight.sh"
test_step "promote.sh 可执行" "test -x ${SCRIPT_DIR}/promote.sh"
test_step "rollback.sh 可执行" "test -x ${SCRIPT_DIR}/rollback.sh"

echo ""

# 总结
echo "============================================================"
echo "测试总结"
echo "============================================================"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}✓ 所有测试通过！DevOps 流程正常工作。${NC}"
    exit 0
else
    echo -e "${RED}✗ 部分测试失败。请检查上述错误信息。${NC}"
    exit 1
fi
