# DevOps 快速启动指南

> 5 分钟快速体验 DevOps 全流程

## 网络拓扑

```
Windows (本地浏览器/kubectl)
    │
    │ plink SSH 隧道 (端口转发)
    ▼
Mac (192.168.29.102)
    │
    │ 内部网络
    ▼
Multipass VM (master 192.168.252.10 / worker1 .11 / worker2 .12)
    │
    ▼
K8s 集群 (NodePort / Ingress)
```

**所有服务都要通过 plink 隧道从 Windows 访问**，区别在于：
- Gitea / Jenkins / myapp → 走 **Ingress (443 HTTPS)**，域名区分
- 其他服务 → 走各自的 **NodePort**

---

## 服务访问地址总表

### 通过 Ingress 访问 (端口 443)

| 服务 | 本地地址 | 集群内地址 | 凭证 |
|------|---------|-----------|------|
| Gitea | `https://gitea.3hang.asia` | `http://gitea.devops:3000` | david / 12345678 |
| Jenkins | `https://jenkins.3hang.asia` | `http://jenkins.devops:8080` | admin / 12345678 |
| myapp | `http://myapp.3hang.asia` | `http://myapp.myapp:80` | 无 |

> Ingress 入口 NodePort: `32501`，plink 转发到本地 `443`

### 通过 NodePort 直接访问

| 服务 | 本地地址 (plink 转发后) | 集群内地址 | 凭证 |
|------|------------------------|-----------|------|
| SonarQube | `http://localhost:30900` | `http://sonarqube.devops:9000` | admin / admin |
| Harbor | `http://localhost:30080` | `http://harbor.devops:80` | 无认证 |
| Nexus | `http://localhost:30881` | `http://nexus.devops:8081` | exec 获取 |
| ArgoCD | `http://localhost:30890` | `http://argocd-server.argocd:80` | admin / admin123 |
| Prometheus | `http://localhost:30909` | `http://prometheus.devops:9090` | 无 |
| Grafana | `http://localhost:30301` | `http://grafana.devops:3000` | admin / admin |
| Elasticsearch | `http://localhost:30920` | `http://elasticsearch.devops:9200` | 无 |
| Kibana | `http://localhost:30601` | `http://kibana.devops:5601` | 无 |
| Vault | `http://localhost:30820` | `http://vault.devops:8200` | Token: devroot |
| Gitea (HTTP 备用) | `http://localhost:30300` | `http://gitea.devops:3000` | 同 Ingress |

### 集群内专用地址 (服务间调用)

以下地址**仅在集群内部**有效，Jenkins Pipeline / ArgoCD / Webhook 等内部通信使用：

| 调用方 | 目标服务 | 地址 |
|--------|---------|------|
| Jenkins → Gitea API | Gitea | `http://gitea.devops:3000` |
| Jenkins → Harbor | Harbor | `http://harbor.devops:80` |
| Jenkins → SonarQube | SonarQube | `http://sonarqube.devops:9000` |
| Jenkins Webhook | Gitea Webhook 回调 | `http://jenkins.devops:8080/gitea-webhook/post` |
| ArgoCD → K8s API | Kubernetes | `https://kubernetes.default.svc` |
| Prometheus → 应用 | myapp metrics | `http://myapp.myapp:80/healthz` |

---

## 前置条件

### 步骤 1: 建立 plink 隧道

需要转发**所有** NodePort 端口，一次性配好：

```powershell
# PowerShell (管理员) — 一条命令转发所有端口
plink -hostkey SHA256:egsS6K3yBfEiWfXKVdZdvR+rzmWw+6P7cbADttlUnZU `
  -L 443:192.168.252.10:32501 `
  -L 16443:192.168.252.10:6443 `
  -L 30300:192.168.252.10:30300 `
  -L 30222:192.168.252.10:30222 `
  -L 30880:192.168.252.10:30880 `
  -L 30900:192.168.252.10:30900 `
  -L 30080:192.168.252.10:30080 `
  -L 30881:192.168.252.10:30881 `
  -L 30890:192.168.252.10:30890 `
  -L 30909:192.168.252.10:30909 `
  -L 30301:192.168.252.10:30301 `
  -L 30920:192.168.252.10:30920 `
  -L 30601:192.168.252.10:30601 `
  -L 30820:192.168.252.10:30820 `
  admin@192.168.29.102 -pw 123456 -N
```

| 本地端口 | 远程目标 | 用途 |
|---------|---------|------|
| 443 | 192.168.252.10:32501 | Ingress HTTPS (Gitea + Jenkins + myapp) |
| 16443 | 192.168.252.10:6443 | K8s API Server (kubectl) |
| 30300 | 192.168.252.10:30300 | Gitea NodePort HTTP (备用) |
| 30222 | 192.168.252.10:30222 | Gitea SSH |
| 30880 | 192.168.252.10:30880 | Jenkins NodePort (备用) |
| 30900 | 192.168.252.10:30900 | SonarQube |
| 30080 | 192.168.252.10:30080 | Harbor |
| 30881 | 192.168.252.10:30881 | Nexus |
| 30890 | 192.168.252.10:30890 | ArgoCD |
| 30909 | 192.168.252.10:30909 | Prometheus |
| 30301 | 192.168.252.10:30301 | Grafana |
| 30920 | 192.168.252.10:30920 | Elasticsearch |
| 30601 | 192.168.252.10:30601 | Kibana |
| 30820 | 192.168.252.10:30820 | Vault |

### 步骤 2: 配置 hosts 文件

编辑 `C:\Windows\System32\drivers\etc\hosts`:

```
127.0.0.1  gitea.3hang.asia jenkins.3hang.asia myapp.3hang.asia
```

---

## 快速开始 (5 分钟)

### 1. 部署应用

```bash
export KUBECONFIG=d:/code/k8s/cka-cluster-config

# 创建 namespace
kubectl apply -f cka/app/myapp/k8s/00-namespace.yaml

# 部署 stable
kubectl apply -f cka/app/myapp/k8s/10-stable-deploy.yaml

# 部署 canary
kubectl apply -f cka/app/myapp/k8s/20-canary-deploy.yaml

# 部署 Ingress
kubectl apply -f cka/app/myapp/k8s/30-ingress.yaml

# 验证
kubectl get all -n myapp
```

### 2. 访问应用

```bash
# 通过 Ingress 域名访问 (走 443 隧道)
curl -H "Host: myapp.3hang.asia" http://localhost:30300
```

### 3. 测试灰度发布

```bash
# 10% 流量切换到 canary
./cka/app/myapp/scripts/canary-weight.sh 10

# 验证流量分配
for i in {1..10}; do
  curl -sH "Host: myapp.3hang.asia" http://localhost:30300 | grep version
done

# 全量发布 (canary → stable)
./cka/app/myapp/scripts/promote.sh

# 一键回滚
./cka/app/myapp/scripts/rollback.sh
```

---

## 完整 CI/CD 流程

### 1. 初始化 GitOps 仓库

```bash
cd cka/app/myapp
./scripts/init-gitops-repo.sh
```

### 2. 配置 Jenkins Pipeline

1. 访问 https://jenkins.3hang.asia
2. 登录：admin / 12345678
3. New Item → `myapp-ci` → Pipeline
4. Pipeline script from SCM:
   - SCM: Git
   - Repository URL: `https://gitea.3hang.asia/devops/myapp-src.git`
   - Credentials: `gitea-https`
   - Branch: `*/main`
   - Script Path: `src/Jenkinsfile`

### 3. 配置 Gitea Webhook

1. 访问 https://gitea.3hang.asia/devops/myapp-src
2. Settings → Webhooks → Add Webhook
3. Payload URL: `http://jenkins.devops:8080/gitea-webhook/post`
4. Content type: `application/json`
5. Events: `Push`

### 4. 触发流水线

```bash
# 修改源代码并 push
cd cka/app/myapp/src-repo
echo "<!-- test -->" >> src/index.html
git add .
git commit -m "test: trigger CI/CD pipeline"
git push origin main
```

### 5. 观察流程

1. Jenkins 自动触发构建 → https://jenkins.3hang.asia/job/myapp-ci/
2. 验证镜像推送到 Harbor → http://localhost:30080
3. 验证 GitOps 仓库更新 → https://gitea.3hang.asia/devops/myapp-k8s
4. 验证 ArgoCD 自动同步 → http://localhost:30890

---

## 常用命令

### 查看资源状态

```bash
export KUBECONFIG=d:/code/k8s/cka-cluster-config

# 查看所有资源
kubectl get all -n myapp

# 查看部署
kubectl get deployments -n myapp

# 查看 Pods
kubectl get pods -n myapp -o wide

# 查看日志
kubectl logs -n myapp deploy/myapp -f

# 查看 Ingress
kubectl get ingress -n myapp

# 查看灰度权重
kubectl get ingress myapp-canary -n myapp -o yaml
```

### 灰度发布

```bash
# 调整权重 (0-100)
./scripts/canary-weight.sh 10

# 全量发布
./scripts/promote.sh

# 回滚
./scripts/rollback.sh
```

### 运行测试

```bash
# 端到端测试
./scripts/test-devops-flow.sh

# 快速测试
./scripts/test-devops-flow.sh --quick
```

---

## 故障排查

### Pod 无法启动

```bash
# 查看 Pod 事件
kubectl describe pod -n myapp <pod-name>

# 查看日志
kubectl logs -n myapp <pod-name> --previous
```

### Ingress 无法访问

```bash
# 检查 plink 隧道是否建立
netstat -an | findstr "443"

# 检查 Ingress Controller
kubectl get pods -n ingress-nginx

# 测试 Ingress
curl -H "Host: myapp.3hang.asia" http://localhost:30300
```

### Jenkins 流水线失败

```bash
# 查看 Jenkins 日志
kubectl logs -n devops deploy/jenkins

# 检查凭证
# Jenkins UI → Manage Jenkins → Credentials

# 检查集群内 Gitea 连通性 (从 Jenkins pod 内测试)
kubectl exec -n devops deploy/jenkins -- curl -I http://gitea.devops:3000
```

---

## 清理资源

```bash
# 删除所有资源 (保留 namespace)
kubectl delete all -n myapp --all

# 删除 namespace
kubectl delete namespace myapp

# 删除 Ingress
kubectl delete ingress -n myapp --all
```

---

## 下一步

- 查看详细规划：[03-devops-plan.md](03-devops-plan.md)
- 查看 myapp 文档：[myapp/README.md](../app/myapp/README.md)
- 查看工具链部署：[devopsyaml/README.md](../devopsyaml/README.md)
