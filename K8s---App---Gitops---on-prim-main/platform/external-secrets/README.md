# External Secrets Operator (ESO)

ESO يقرأ من **HashiCorp Vault** وينشئ/يحدّث `Secret` في Kubernetes (مثل `mysql-secret`) بدون وضع القيم في Git.

## تثبيت (مرة واحدة على الكلاستر)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true
```

تحقق:

```bash
kubectl get pods -n external-secrets
kubectl api-resources | grep external-secrets
```

## Vault

راجع [platform/vault/README.md](../vault/README.md) لإعداد KV و Kubernetes auth والـ policies.

## تطبيق manifests التطبيق

بعد ضبط `VAULT_ADDR` و الـ roles في الـ overlays:

```bash
kubectl apply -k apps/overlays/production/
kubectl apply -k apps/overlays/development/
```

تحقق من المزامنة:

```bash
kubectl get secretstore,externalsecret -n vprofile
kubectl describe externalsecret mysql-secret -n vprofile
kubectl get secret mysql-secret -n vprofile
```
