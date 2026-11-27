#!/usr/bin/env bash
# Kubernetes made the disks (and later the ALB), so remove them first, then terraform destroy
set -euo pipefail
cd "$(dirname "$0")"
aws eks update-kubeconfig --name leaky-pipeline --region us-east-1 >/dev/null

echo "== 1/4 stop ArgoCD recreating things, unlock ClickHouse =="
kubectl delete application root -n argocd --ignore-not-found
kubectl patch clickhouseinstallations.clickhouse.altinity.com -n signoz --all --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

echo "== 2/4 delete apps (operators stay up to clean up) =="
kubectl get applications -n argocd -o name | grep -vE '/(strimzi|mongodb-operator|vso|storage)$' | xargs -r kubectl delete -n argocd

echo "== 3/4 delete disks, wait until AWS has removed them =="
kubectl delete pvc --all -A
until [ -z "$(kubectl get pv -o name)" ]; do echo "  disks still deleting..."; sleep 10; done
kubectl delete applications -n argocd --all

echo "== 4/4 terraform destroy =="
terraform destroy -auto-approve
echo "== done =="