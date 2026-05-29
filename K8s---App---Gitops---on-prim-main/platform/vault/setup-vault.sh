#!/usr/bin/env bash
# تثبيت Vault (dev) + إعداد KV و Kubernetes auth لـ vprofile / vprofile-dev
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALUES="${ROOT}/platform/vault/values-dev.yaml"

if [[ ! -f "${VALUES}" ]]; then
  ROOT="${ROOT}/K8s---App---Gitops---on-prim-main"
  VALUES="${ROOT}/platform/vault/values-dev.yaml"
fi

if [[ ! -f "${VALUES}" ]]; then
  echo "ERROR: values-dev.yaml not found. pwd=$(pwd) tried ${VALUES}" >&2
  exit 1
fi

echo "==> Using values: ${VALUES}"

helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update hashicorp

kubectl create namespace vault 2>/dev/null || true

helm upgrade --install vault hashicorp/vault \
  -n vault \
  -f "${VALUES}"

echo "==> Waiting for Vault pod..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=vault \
  -n vault \
  --timeout=180s

VAULT_POD="$(kubectl get pod -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')"
echo "==> Vault pod: ${VAULT_POD}"

kubectl exec -n vault "${VAULT_POD}" -- sh -c '
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=root

  vault secrets enable -path=secret kv-v2 2>/dev/null || true

  vault kv put secret/vprofile/mysql \
    MYSQL_ROOT_PASSWORD=admin123 \
    MYSQL_DATABASE=accounts \
    MYSQL_USER=admin \
    MYSQL_PASSWORD=admin123

  vault kv put secret/vprofile-dev/mysql \
    MYSQL_ROOT_PASSWORD=dev123 \
    MYSQL_DATABASE=accounts \
    MYSQL_USER=admin \
    MYSQL_PASSWORD=dev123

  vault auth enable kubernetes 2>/dev/null || true

  vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"

  vault policy write vprofile-mysql - <<EOF
path "secret/data/vprofile/mysql" {
  capabilities = ["read"]
}
EOF

  vault write auth/kubernetes/role/vprofile-mysql \
    bound_service_account_names=vault-mysql \
    bound_service_account_namespaces=vprofile \
    policies=vprofile-mysql \
    ttl=1h

  vault policy write vprofile-dev-mysql - <<EOF
path "secret/data/vprofile-dev/mysql" {
  capabilities = ["read"]
}
EOF

  vault write auth/kubernetes/role/vprofile-dev-mysql \
    bound_service_account_names=vault-mysql \
    bound_service_account_namespaces=vprofile-dev \
    policies=vprofile-dev-mysql \
    ttl=1h

  echo "Vault KV + kubernetes auth configured."
'

echo ""
echo "Done. Next:"
echo "  git pull"
echo "  kubectl apply -k apps/overlays/production/"
echo "  kubectl get secretstore vault-backend -n vprofile"
echo "  kubectl get externalsecret mysql-secret -n vprofile"
