# HashiCorp Vault — on-prem مع Kubernetes

هذا الدليل يكمّل manifests في `apps/overlays/*/vault/`. القيم الحساسة تبقى في Vault فقط.

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
