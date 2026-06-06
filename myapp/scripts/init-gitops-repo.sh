#!/usr/bin/env bash
# =============================================================
# init-gitops-repo.sh — 初始化 GitOps 配置仓库
#
# 用法：./init-gitops-repo.sh
# 前提：已登录 Gitea (https://gitea.3hang.asia)
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/gitops-repo"
GITEA_URL="https://gitea.3hang.asia"
ORG="devops"
REPO_NAME="myapp-k8s"

echo "============================================================"
echo "GitOps Repository Initialization"
echo "============================================================"
echo ""

# 1. 检查 Gitea 仓库是否存在
echo "[1/6] Checking Gitea repository..."
if curl -s -o /dev/null -w "%{http_code}" "${GITEA_URL}/${ORG}/${REPO_NAME}" | grep -q "200"; then
    echo "✓ Repository exists: ${GITEA_URL}/${ORG}/${REPO_NAME}"
else
    echo "⚠ Repository not found. Please create it manually:"
    echo "  1. Visit: ${GITEA_URL}"
    echo "  2. Login: david / 12345678"
    echo "  3. New Repository → Owner: ${ORG}, Name: ${REPO_NAME}"
    echo "  4. Visibility: Private (recommended)"
    exit 1
fi

# 2. 创建本地仓库目录
echo ""
echo "[2/6] Creating local repository directory..."
mkdir -p "${REPO_DIR}"
cd "${REPO_DIR}"

# 3. 初始化 Git 仓库
echo ""
echo "[3/6] Initializing Git repository..."
if [ ! -d ".git" ]; then
    git init
    git checkout -b main
else
    echo "✓ Git repository already initialized"
fi

# 4. 复制 K8s 配置文件
echo ""
echo "[4/6] Copying K8s manifests..."
mkdir -p k8s
cp -v "${SCRIPT_DIR}/k8s/"*.yaml k8s/

# 5. 创建 README.md
echo ""
echo "[5/6] Creating README.md..."
cat > README.md << 'EOF'
# myapp-k8s

GitOps 配置仓库，由 ArgoCD 自动同步到 Kubernetes 集群。

## 目录结构

```
k8s/
├── 00-namespace.yaml          # myapp namespace
├── 01-network-policy.yaml     # NetworkPolicy 隔离
├── 10-stable-deploy.yaml      # 稳定版 Deployment + Service
├── 20-canary-deploy.yaml      # 灰度版 Deployment + Service
├── 30-ingress.yaml            # Ingress 配置 (stable + canary)
└── 40-argocd-app.yaml         # ArgoCD Application
```

## 自动同步

ArgoCD 监控 main 分支，自动应用变更：

- **Sync Policy**: Automatic
- **Prune Resources**: Enabled
- **Self Heal**: Enabled

## 镜像更新流程

1. 开发者 push 代码到 myapp-src 仓库
2. Jenkins 触发 CI/CD 流水线
3. 构建新镜像并推送到 Harbor
4. Jenkins 更新 k8s/ 中的 image tag
5. 提交到本仓库 main 分支
6. ArgoCD 自动同步并部署

## 灰度发布

通过修改 `k8s/30-ingress.yaml` 中的 canary-weight 注解调整流量：

```bash
# 10% 流量到 canary
./scripts/canary-weight.sh 10

# 全量发布
./scripts/promote.sh

# 回滚
./scripts/rollback.sh
```

## 相关仓库

- **应用源码**: https://gitea.3hang.asia/devops/myapp-src
- **GitOps 配置**: https://gitea.3hang.asia/devops/myapp-k8s (本仓库)

## 访问地址

| 环境 | 地址 |
|------|------|
| Stable | https://myapp.3hang.asia |
| Canary | https://myapp.3hang.asia (通过权重控制) |
EOF

# 6. 提交并推送
echo ""
echo "[6/6] Committing and pushing to Gitea..."
git add .
git commit -m "chore: initial GitOps repository with K8s manifests" || echo "No changes to commit"

# 配置远程仓库
if ! git remote get-url origin &>/dev/null; then
    git remote add origin "${GITEA_URL}/${ORG}/${REPO_NAME}.git"
fi

# 推送
echo ""
echo "Pushing to ${GITEA_URL}/${ORG}/${REPO_NAME}..."
git push -u origin main

echo ""
echo "============================================================"
echo "✓ GitOps repository initialized successfully!"
echo ""
echo "Repository: ${GITEA_URL}/${ORG}/${REPO_NAME}"
echo "Local path: ${REPO_DIR}"
echo ""
echo "Next steps:"
echo "1. Configure ArgoCD to sync this repository"
echo "2. Create Jenkins pipeline for myapp-src"
echo "3. Test the CI/CD flow"
echo "============================================================"
