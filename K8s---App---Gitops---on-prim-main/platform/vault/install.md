# تثبيت Vault على الكلاستر (خطوة إلزامية)

> **لو `kubectl get svc -A | grep vault` فاضي** → Vault مش موجود. ESO مش هيعرف يشتغل قبل التثبيت.

## ⚠️ مسار الريبو على jump

```bash
pwd
# /home/ahmed/K8s-App-Gitops-on-prem/K8s---App---Gitops---on-prim-main

ls platform/vault/values-dev.yaml   # ← هنا
```

**مفيش** مجلد `K8s---App---Gitops---on-prim-main/` جوه — ده بس في GitHub paths.

```bash
cd ~/K8s-App-Gitops-on-prem/K8s---App---Gitops---on-prim-main
./platform/vault/setup-vault.sh
```

## ⚠️ متعملش Ctrl+C أثناء helm

`helm upgrade --install ... --wait` بياخد 1–3 دقائق. Ctrl+C يقطع التثبيت ويخلي namespace فاضي.

## ⚠️ خطأ `etcdserver: request timed out`

ده **مش** خطأ Vault — ده **control plane / etcd** على الكلاستر بطيء أو تحت ضغط.

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep -E 'etcd|apiserver'
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

**على control plane node(s):**
```bash
df -h                    # disk full؟
free -h                  # RAM
sudo crictl ps | grep etcd
```

**حلول شائعة:**
- Disk > 85% على control plane → نظّف (`journalctl --vacuum`, old images)
- etcd pod مش Running → `kubectl describe pod -n kube-system -l component=etcd`
- Worker nodes NotReady → أصلحهم الأول
- **استنى 2–3 دقائق** وجرب helm تاني (مرة واحدة، بدون Ctrl+C)

```bash
helm upgrade --install vault hashicorp/vault \
  -n vault \
  -f platform/vault/values-dev.yaml \
  --wait --timeout 10m
```

## يدوي — أمر واحد في كل مرة (مهم: متعملش Ctrl+C)

### 0. تأكد من المسار

```bash
ls platform/vault/values-dev.yaml
# لو File not found:
ls K8s---App---Gitops---on-prim-main/platform/vault/values-dev.yaml
```

### 1. Helm

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### 2. Namespace + تثبيت

```bash
kubectl create namespace vault
```

```bash
helm upgrade --install vault hashicorp/vault \
  -n vault \
  -f platform/vault/values-dev.yaml
```

**استنى لحد ما يخلص** — لازم تشوف `Release "vault" has been upgraded` أو `deployed`.

### 3. تحقق

```bash
kubectl get pods -n vault
kubectl get svc -n vault
helm list -n vault
```

> **dev mode:** الـ pod اسمه `vault-xxxxxxxx-xxxxx` (Deployment) — **مش** `vault-0`.

```bash
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault -n vault --timeout=180s
```

```bash
export VAULT_POD=$(kubectl get pod -n vault -l app.kubernetes.io/name=vault \
  -o jsonpath='{.items[0].metadata.name}')
echo $VAULT_POD
```

### 4. إعداد KV + auth (استخدم $VAULT_POD)

```bash
kubectl exec -n vault "$VAULT_POD" -- sh -c '
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=root
  vault secrets enable -path=secret kv-v2 2>/dev/null || true
  vault kv put secret/vprofile/mysql \
    MYSQL_ROOT_PASSWORD=admin123 MYSQL_DATABASE=accounts \
    MYSQL_USER=admin MYSQL_PASSWORD=admin123
  vault auth enable kubernetes 2>/dev/null || true
  vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
  vault policy write vprofile-mysql - <<EOF
path "secret/data/vprofile/mysql" { capabilities = ["read"] }
EOF
  vault write auth/kubernetes/role/vprofile-mysql \
    bound_service_account_names=vault-mysql \
    bound_service_account_namespaces=vprofile \
    policies=vprofile-mysql ttl=1h
'
```

## 5. عنوان Vault لـ External Secrets

```yaml
server: http://vault.vault.svc.cluster.local:8200
```

```bash
git pull
kubectl apply -k apps/overlays/production/
kubectl describe secretstore vault-backend -n vprofile
```

## 6. تحقق نهائي

```bash
kubectl get secretstore vault-backend -n vprofile
kubectl get externalsecret mysql-secret -n vprofile
kubectl get secret mysql-secret -n vprofile
```

## استكشاف أخطاء

| المشكلة | الحل |
|---------|------|
| `pods "vault-0" not found` | dev mode — استخدم `$VAULT_POD` (§3) |
| `values-dev.yaml` not found | `cd` للمجلد الصح (§0) |
| helm اتقطع بـ Ctrl+C | `helm list -n vault` — لو فاضي، أعد §2 |
| ESO webhook timeout | `kubectl rollout restart deployment -n external-secrets` ثم انتظر 2 دقيقة |

## Vault CLI (اختياري على jump)

```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y vault
```

## خطأ webhook ESO (context deadline exceeded)

`cert-controller` و `webhook` لازم **1/1 Ready** — لو 0/1 كل apply بيفشل.

```bash
kubectl get pods -n external-secrets
kubectl describe pod -n external-secrets -l app.kubernetes.io/name=external-secrets-webhook
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets-cert-controller --tail=30
```

**إعادة تثبيت ESO:**

```bash
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --set installCRDs=true \
  --wait --timeout 5m

kubectl get pods -n external-secrets -w
# استنى: 3 pods كلهم 1/1 Running
```

**تطبيق مؤقت بدون webhook** (kubectl patch ما بيدعم `--validate`):

```bash
# 1) شوف webhooks
kubectl get validatingwebhookconfiguration | grep external

# 2) عطّل مؤقتاً (أعد تثبيت ESO بعدها ليرجعوا)
kubectl delete validatingwebhookconfiguration \
  secretstore-validate \
  externalsecret-validate 2>/dev/null || true

# 3) عدّل secret-store مباشرة
kubectl edit secretstore vault-backend -n vprofile
# غيّر server إلى: http://vault.vault.svc.cluster.local:8200

kubectl apply -k apps/overlays/production/

# 4) أعد ESO عشان webhooks ترجع
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --set installCRDs=true --wait --timeout 10m
```
