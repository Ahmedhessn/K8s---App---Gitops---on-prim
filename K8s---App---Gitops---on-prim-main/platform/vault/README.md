# HashiCorp Vault — on-prem مع Kubernetes

هذا الدليل يكمّل manifests في `apps/overlays/*/vault/`. القيم الحساسة تبقى في Vault فقط.

## 0. Vault لازم يكون شغال أولاً

```bash
kubectl get svc -A | grep -i vault   # لو فاضي → Vault مش موجود
```

**ثبّت Vault:** [platform/vault/install.md](./install.md)

بعد التثبيت، غيّر `server` في `secret-store.yaml` من placeholder إلى:

```yaml
server: http://vault.vault.svc.cluster.local:8200   # dev mode
```

`vault.el30mda.local` **مش موجود** في DNS — لا تستخدمه إلا بعد إضافته في CoreDNS أو DNS خارجي.

## 1. تفعيل KV v2 (مثال mount اسمه `secret`)

```bash
vault secrets enable -path=secret kv-v2
# لو الـ mount موجود مسبقاً، تخطّى
```

## 2. كتابة أسرار MySQL لكل بيئة

المفاتيح يجب أن تطابق ما يتوقعه image الـ MySQL (`envFrom` على `mysql-secret`).

**Production** (`vprofile`):

```bash
vault kv put secret/vprofile/mysql \
  MYSQL_ROOT_PASSWORD='CHANGE_ME' \
  MYSQL_DATABASE='accounts' \
  MYSQL_USER='admin' \
  MYSQL_PASSWORD='CHANGE_ME'
```

**Development** (`vprofile-dev`):

```bash
vault kv put secret/vprofile-dev/mysql \
  MYSQL_ROOT_PASSWORD='CHANGE_ME_DEV' \
  MYSQL_DATABASE='accounts' \
  MYSQL_USER='admin' \
  MYSQL_PASSWORD='CHANGE_ME_DEV'
```

## 3. Kubernetes auth في Vault

```bash
vault auth enable kubernetes
# أو: vault auth enable -path=kubernetes kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://KUBERNETES_SERVICE_HOST:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
```

> على سيرفر Vault خارج الكلاستر: استخدم `kubectl cluster-info` و CA من الكلاستر، أو شغّل الأمر من pod داخل الكلاستر.

## 4. Policies و Roles

**Production** — policy:

```hcl
path "secret/data/vprofile/mysql" {
  capabilities = ["read"]
}
```

```bash
vault policy write vprofile-mysql - <<'EOF'
path "secret/data/vprofile/mysql" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/vprofile-mysql \
  bound_service_account_names=vault-mysql \
  bound_service_account_namespaces=vprofile \
  policies=vprofile-mysql \
  ttl=1h
```

**Development** — نفس الفكرة مع `vprofile-dev` و path `secret/data/vprofile-dev/mysql`.

## 5. ضبط عنوان Vault في Git

في كل overlay عدّل `secret-store.yaml`:

- `spec.provider.vault.server` → عنوان Vault الحقيقي (مثال `https://vault.el30mda.local:8200`)

## 6. ترحيل من secret يدوي

```bash
# لو عندك secret قديم على الكلاستر
kubectl get secret mysql-secret -n vprofile -o jsonpath='{.data}' 

# انسخ القيم إلى Vault (بعد decode) ثم احذف اليدوي بعد ما ESO يشتغل:
# kubectl delete secret mysql-secret -n vprofile
# kubectl apply -k apps/overlays/production/
```

## مسار البيانات

```
Vault KV (secret/vprofile/mysql)
    → ExternalSecret (mysql-secret)
    → Kubernetes Secret mysql-secret
    → Deployment mysql (envFrom)
```

## استكشاف الأخطاء — SecretStore مش Ready

### 1. شوف سبب الفشل بالظبط

```bash
kubectl describe secretstore vault-backend -n vprofile
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50
```

في `Status.Conditions` هتلاقي رسالة زي:
- `connection refused` / `no such host` → عنوان Vault غلط أو مش reachable من الكلاستر
- `certificate signed by unknown authority` → TLS (شوف §3)
- `permission denied` / `invalid role` → Kubernetes auth أو role مش موجود في Vault
- `secret not found` → الـ SecretStore شغال؛ المشكلة في path `vprofile/mysql` (§2)

### 2. تأكد إن Vault فيه البيانات

```bash
vault kv get secret/vprofile/mysql
vault read auth/kubernetes/role/vprofile-mysql
vault policy read vprofile-mysql
```

### 3. TLS (on-prem شائع)

لو Vault بشهادة self-signed، أضف تحت `server:` في `secret-store.yaml`:

```yaml
      caProvider:
        type: Secret
        name: vault-ca
        key: ca.crt
        namespace: vprofile
```

أو مؤقتاً للاختبار فقط:

```yaml
      # skipTLSVerify: true
```

### 4. تأكد إن الـ role يطابق الـ ServiceAccount

| Vault role | SA | Namespace |
|------------|-----|-----------|
| `vprofile-mysql` | `vault-mysql` | `vprofile` |
| `vprofile-dev-mysql` | `vault-mysql` | `vprofile-dev` |

```bash
kubectl get sa vault-mysql -n vprofile
```

### 5. اختبار من داخل الكلاستر

```bash
kubectl run vault-test -n vprofile --rm -it --restart=Never \
  --image=curlimages/curl -- \
  curl -sk https://vault.el30mda.local:8200/v1/sys/health
```

### 6. أسماء الملفات في الريبو

| الملف | الغرض |
|-------|--------|
| `secret-store.yaml` | اتصال Vault |
| `mysql-external-secret.yaml` | مزامنة mysql-secret (مش `external-secret.yaml`) |
| `serviceaccount.yaml` | SA للـ Kubernetes auth |

### 7. بعد الإصلاح

```bash
kubectl apply -k apps/overlays/production/
kubectl get secretstore vault-backend -n vprofile
kubectl get externalsecret mysql-secret -n vprofile
kubectl get secret mysql-secret -n vprofile
```
