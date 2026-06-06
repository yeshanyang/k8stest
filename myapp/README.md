# myapp — DevOps 全流程测试项目

> 基于 CKA 3 节点 kubeadm 集群，覆盖 **代码管理 → CI → 构建 → 推送 → 灰度发布 → 回滚 → 监控** 完整链路。

## 集群环境（来自 `../README.md`）

| 节点 | CPU | 内存 | 磁盘 | 角色 |
|------|-----|------|------|------|
| master (192.168.252.10) | 2 | 6GB | 20GB | control-plane |
| worker1 (192.168.252.11) | 2 | 12GB | 100GB | worker |
| worker2 (192.168.252.12) | 2 | 12GB | 100GB | worker |

**存储**: local-path-provisioner (dynamic hostPath)
**CNI**: Calico
**Ingress**: nginx (ingress-nginx)
**API**: `127.0.0.1:16443` (SSH Tunnel)

## 架构总览

```
┌──────────────────────────────────────────────────────────────────┐
│                        DevOps Toolchain                          │
│                                                                  │
│  Gitea → Jenkins → SonarQube → Harbor → ArgoCD → k8s (myapp)   │
│  (code)   (CI/CD)    (quality)    (img)     (GitOps)            │
│                     ↕ Trivy    ↕ Prometheus/                   │
│                     (scan)       Grafana/Elastic               │
└──────────────────────────────────────────────────────────────────┘

              ┌────────────────── k8s myapp namespace ──────────────┐
              │                                                      │
              │  ingress-nginx (nginx ingress controller)            │
              │         │                                            │
              │    ┌────┴────────┐                                   │
              │    │             │                                   │
              │  90% stable     10% canary                          │
              │    │             │                                   │
              │  svc:myapp      svc:myapp-canary                     │
              │    │             │                                   │
              │  deploy:v1.0    deploy:v1.1                          │
              │    │             │                                   │
              │  nodeSelector: worker1  nodeSelector: worker2       │
              └──────────────────────────────────────────────────────┘
```

## 流水线 (Pipeline)

```
1. 开发者 push → Gitea (gitea.3hang.asia)
2. Gitea Webhook → Jenkins 触发 CI
3. Jenkins:
   a. 拉取源码
   b. SonarQube 代码扫描 (sonar-scanner)
   c. Trivy 漏洞扫描 (build image → scan)
   d. 构建 Docker 镜像 (tag: <commit-sha>)
   e. 推送镜像到 Harbor (registry.local:30080/myapp/<image>:<tag>)
   f. 更新 k8s manifest (sed 替换 tag)
   g. 提交到 Git ops 分支 (GitOps)
4. ArgoCD 自动同步 → 部署 canary
5. 手动/自动验证 → 调整灰度权重 → 全量发布
6. 可选: 一键回滚
```

## 灰度发布策略

使用 **nginx ingress 权重路由**，在 Service 层面做 90/10 切分:

| 阶段 | stable | canary | 说明 |
|------|--------|--------|------|
| 初始部署 | 100% | 0% | 先部署 canary 但不放流量 |
| 小流量验证 | 90% | 10% | 验证新功能 |
| 扩大灰度 | 70% | 30% | 继续验证 |
| 全量发布 | 0% | 100% | canary 成为主版本 |
| 回滚 | 100% | 0% | 切换回 stable |

## 资源规划

> 集群总 CPU 6 核、总内存 30GB。DevOps 工具链已占用大量资源，myapp 需轻量部署。

| 组件 | CPU req | CPU lim | Mem req | Mem lim | replicas |
|------|---------|---------|---------|---------|----------|
| stable | 100m | 200m | 64Mi | 128Mi | 2 |
| canary | 100m | 200m | 64Mi | 128Mi | 1 |

## 网络规划

| 资源 | 说明 |
|------|------|
| Ingress host | `myapp.3hang.asia` (同域名, nginx 内部权重路由) |
| NetworkPolicy | 仅允许 ingress-nginx namespace 访问 myapp Service |
| NodeSelector | stable → worker1, canary → worker2 (跨节点隔离) |

## 目录结构

```
cka/app/myapp/
├── README.md                  # 本文件
├── src/
│   ├── index.html             # Sample app (version-aware)
│   ├── Dockerfile             # 容器构建
│   └── Jenkinsfile            # Jenkins CI/CD 流水线
├── k8s/
│   ├── 00-namespace.yaml       # myapp namespace
│   ├── 01-network-policy.yaml  # NetworkPolicy 隔离
│   ├── 10-stable-deploy.yaml   # 稳定版 Deployment + Service
│   ├── 20-canary-deploy.yaml   # 灰度版 Deployment + Service
│   ├── 30-ingress.yaml         # 入口 Ingress (stable + canary 注解)
│   └── 40-argocd-app.yaml      # ArgoCD Application
├── scripts/
│   ├── canary-weight.sh        # 调整灰度权重
│   ├── promote.sh              # 全量发布 (canary → stable)
│   └── rollback.sh             # 一键回滚
```

## 快速开始

### 1. 部署基础资源

```bash
export KUBECONFIG=d:/code/k8s/cka-cluster-config

kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-network-policy.yaml
```

### 2. 首次部署 stable

```bash
kubectl apply -f k8s/10-stable-deploy.yaml
kubectl apply -f k8s/30-ingress.yaml
```

### 3. 灰度发布新版本

```bash
# 部署 canary (修改 images 中的 tag)
kubectl apply -f k8s/20-canary-deploy.yaml

# 10% 流量切到 canary
./scripts/canary-weight.sh 10

# 验证后调整到 30%
./scripts/canary-weight.sh 30

# 全量发布
./scripts/promote.sh

# 回滚
./scripts/rollback.sh
```

### 4. 配置 ArgoCD 自动同步

在 ArgoCD (http://\<node\>:30890) 中:

1. New Application → `myapp`
2. Repository URL: `https://gitea.3hang.asia/devops/myapp-k8s.git`
3. Path: `k8s/`
4. Cluster: `https://kubernetes.default.svc`
5. Namespace: `myapp`
6. Sync Policy: **Automatic**

## 维护命令

```bash
# 查看 myapp 所有资源
kubectl get all -n myapp

# 查看 Ingress
kubectl get ingress -n myapp

# 查看网络策略
kubectl get networkpolicy -n myapp

# 查看 canary 日志
kubectl logs -n myapp deploy/myapp-canary -f

# 查看 stable 日志
kubectl logs -n myapp deploy/myapp -f

# 测试访问
curl -H "Host: myapp.3hang.asia" http://<node-ip>:<ingress-nodeport>
```
