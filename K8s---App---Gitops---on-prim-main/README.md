# K8s App GitOps (On-Prem)

مستودع manifests مأخوذ من **كلاستر شغال** — نفس الـ namespaces والـ hosts والـ ports، منظم بـ **Kustomize**.

## الهيكل

```
apps/
  base/
    deployments/           # apps, memcached, mysql, rabbitmq
    services.yaml
    ingress.yaml
  overlays/
    development/           # namespace: vprofile-dev, host: dev.el30mda.local
    production/            # namespace: vprofile, host: el30mda.local
    monitoring/            # Grafana + Prometheus ingress
cluster-setup/             # metrics-server, RBAC
platform/
  vault/                   # إعداد Vault (KV, policies, k8s auth)
  external-secrets/        # تثبيت ESO
environments/              # اختصار — يوجّه لـ apps/overlays/*
scripts/render.ps1         # بناء YAML للمراجعة
```

## أوامر سريعة

```powershell
# بناء كل البيئات إلى .render/
.\scripts\render.ps1

# بيئة واحدة
.\scripts\render.ps1 -Environment production

# تطبيق (بعد kubectl diff)
kubectl apply -k apps/overlays/production/
kubectl apply -k apps/overlays/development/
kubectl apply -k apps/overlays/monitoring/
kubectl apply -f cluster-setup/
```

## تطبيق آمن على كلاستر موجود

1. `kubectl diff -k apps/overlays/production/`
2. `kubectl apply --dry-run=server -k apps/overlays/production/`
3. لو الفرق متوقع (labels / حذف annotations قديمة) → `kubectl apply -k ...`

> **Namespace:** الـ overlay يتضمن `Namespace` — لو موجود مسبقاً على الكلاستر، `apply` آمن (تحديث labels فقط).

> **Services:** بدون `clusterIP` في Git — الكلاستر يحتفظ بالـ IP الحالي.

> **Deployments:** في `apps/base/deployments/` — صور من الكلاستر الشغال.
>
> **mysql-secret:** يُدار عبر **Vault + External Secrets** (`apps/overlays/*/vault/`). راجع `platform/vault/README.md`.
>
> **mysql-pvc:** لازم يكون موجود على الكلاستر (مش في Git).
>
> **production فقط:** `rabbitmq-patch.yaml` (nodeSelector `worker1` + `RABBITMQ_MNESIA_DIR`).

## dev vs production

| | Development | Production |
|---|-------------|------------|
| Namespace | `vprofile-dev` | `vprofile` |
| Ingress host | `dev.el30mda.local` | `el30mda.local` |
| Overlay | `apps/overlays/development` | `apps/overlays/production` |

## Kustomize — إزاي يشتغل

```
base (deployments + services + ingress)
    ↓
overlay يضيف:
  - namespace لكل الموارد
  - label: environment
  - patch: host الـ Ingress فقط
```

**مهم:** `includeSelectors: false` عشان label `environment` ما يتضافش على `selector` ويكسر ربط الـ Pods.

## Vault + External Secrets (mysql-secret)

1. ثبّت ESO: `platform/external-secrets/README.md`
2. اضبط Vault: `platform/vault/README.md` (KV + kubernetes auth + roles)
3. عدّل `server` في `apps/overlays/*/vault/secret-store.yaml`
4. `kubectl apply -k apps/overlays/production/`

```bash
kubectl get externalsecret,secretstore -n vprofile
kubectl describe externalsecret mysql-secret -n vprofile
```

## قبل apply الـ Deployments

```bash
# تأكد إن ESO مزامن secret و pvc موجود
kubectl get secret mysql-secret -n vprofile
kubectl get pvc mysql-pvc -n vprofile

# قارن dev مع prod (لو rabbitmq مختلف)
diff <(kubectl get deploy rabbitmq -n vprofile -o yaml) \
     <(kubectl get deploy rabbitmq -n vprofile-dev -o yaml) | head -40

kubectl diff -k apps/overlays/production/
```

## الخطوة الجاية (اختياري)

- Argo CD `Application` يشير لـ `apps/overlays/production`
- أسرار إضافية (RabbitMQ، registry) بنفس نمط `ExternalSecret`
