#!/usr/bin/env bash
# Kubernetes made the disks and the ALB, so remove them first, then terraform destroy
set -euo pipefail
cd "$(dirname "$0")"
aws eks update-kubeconfig --name leaky-pipeline --region us-east-1 >/dev/null
# echo "== 1/4 stop ArgoCD recreating things, unlock ClickHouse =="
# echo "== 1/5 stop ArgoCD recreating things, unlock ClickHouse =="
echo "== 1/5 stop ArgoCD recreating things =="
kubectl delete application root -n argocd --ignore-not-found
# patch has no --all, and "|| true" hid the error - unlock moved into step 2
# kubectl patch clickhouseinstallations.clickhouse.altinity.com -n signoz --all --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
# echo "== 2/4 delete apps (operators stay up to clean up) =="
echo "== 2/5 delete apps (operators stay up to clean up) =="
# kubectl get applications -n argocd -o name | grep -vE '/(strimzi|mongodb-operator|vso|storage)$' | xargs -r kubectl delete -n argocd
KEEP='/(strimzi|mongodb-operator|vso|storage)$'
# --wait=false: start deleting, don't block - the loop below waits
kubectl get applications -n argocd -o name | grep -vE "$KEEP" | xargs -r kubectl delete -n argocd --wait=false
# ClickHouse's operator re-adds its lock, so remove it on every round until the apps are gone
until [ -z "$(kubectl get applications -n argocd -o name | grep -vE "$KEEP")" ]; do
  CHI=$(kubectl get clickhouseinstallations.clickhouse.altinity.com -n signoz -o name 2>/dev/null || true)
  if [ -n "$CHI" ]; then
    kubectl patch -n signoz $CHI --type merge -p '{"metadata":{"finalizers":[]}}' || echo "  ClickHouse already gone"
  fi
  echo "  apps still deleting..."; sleep 10
done
echo "== 3/5 wait until AWS has removed the shop ALB =="
until [ -z "$(aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --tag-filters Key=elbv2.k8s.aws/cluster,Values=leaky-pipeline \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)" ]; do
  echo "  ALB still deleting..."; sleep 10
done
# echo "== 3/4 delete disks, wait until AWS has removed them =="
echo "== 4/5 delete disks, wait until AWS has removed them =="
kubectl delete pvc --all -A
until [ -z "$(kubectl get pv -o name)" ]; do echo "  disks still deleting..."; sleep 10; done
kubectl delete applications -n argocd --all
# echo "== 4/4 terraform destroy =="
echo "== 5/5 terraform destroy =="
terraform destroy -auto-approve
echo "== done =="