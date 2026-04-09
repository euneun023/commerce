#!/bin/bash
set -euo pipefail

AWS_REGION="ap-northeast-2"
VPC_ID="vpc-xxxxxxxx"
CLUSTER_NAME="eks-mod"

echo "[1] Delete app ingress/service/deployment (non-blocking)"
kubectl delete ingress --all -A --ignore-not-found=true --wait=false || true
kubectl delete svc --all -A --ignore-not-found=true --wait=false || true
kubectl delete deployment --all -A --ignore-not-found=true --wait=false || true
kubectl delete targetgroupbinding --all -A --ignore-not-found=true --wait=false || true
kubectl delete ingressclass --all --ignore-not-found=true --wait=false || true

echo "[1-1] Force remove finalizers that often block deletion"
kubectl patch svc traefik -n traefik -p '{"metadata":{"finalizers":[]}}' --type=merge || true
kubectl patch ns traefik -p '{"spec":{"finalizers":[]}}' --type=merge || true

for tgb in $(kubectl get targetgroupbinding -n traefik -o name 2>/dev/null); do
  kubectl patch "$tgb" -n traefik -p '{"metadata":{"finalizers":[]}}' --type=merge || true
done

echo "[1-2] Delete traefik-specific resources (non-blocking)"
kubectl delete svc traefik -n traefik --ignore-not-found=true --wait=false || true
kubectl delete targetgroupbinding --all -n traefik --ignore-not-found=true --wait=false || true
kubectl delete ns traefik --ignore-not-found=true --wait=false || true

echo "[2] Delete Karpenter resources (non-blocking)"
kubectl delete nodepool --all --ignore-not-found=true --wait=false || true
kubectl delete ec2nodeclass --all --ignore-not-found=true --wait=false || true

echo "[3] Uninstall Helm releases (non-blocking where possible)"
helm uninstall aws-load-balancer-controller -n kube-system --wait || true
helm uninstall karpenter -n kube-system --wait || true
helm uninstall argocd -n argocd --wait || true
helm uninstall traefik -n traefik --wait || true
helm uninstall cert-manager -n cert-manager --wait || true

echo "[3-1] Waiting for AWS Load Balancers to be fully deleted..."
while true; do
  LB_ARNS=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
    --output text 2>/dev/null || true)

  if [ -z "$LB_ARNS" ]; then
    echo "All Load Balancers deleted successfully."
    break
  else
    LB_COUNT=$(echo "$LB_ARNS" | wc -w)
    echo "Still $LB_COUNT Load Balancer(s) remaining... checking again in 20s"
    aws elbv2 describe-load-balancers \
      --region "$AWS_REGION" \
      --query "LoadBalancers[?VpcId=='$VPC_ID'].[LoadBalancerName,State.Code,DNSName]" \
      --output table || true
    sleep 20
  fi
done

echo "[3-2] Cleaning up orphaned ENIs"
ENI_IDS=$(aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=status,Values=available \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' \
  --output text 2>/dev/null || true)

for ENI in $ENI_IDS; do
  echo "Deleting available ENI: $ENI"
  aws ec2 delete-network-interface --region "$AWS_REGION" --network-interface-id "$ENI" || true
done

echo "[4] Wait for AWS resources cleanup"
sleep 60

echo "[5] Check remaining Load Balancers"
aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[*].{Name:LoadBalancerName,VpcId:VpcId,State:State.Code}" \
  --output table || true

aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].[LoadBalancerName,State.Code,DNSName]" \
  --output table || true

echo "[6] Check remaining ENIs in VPC"
aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'NetworkInterfaces[*].{ENI:NetworkInterfaceId,Desc:Description,Status:Status,Subnet:SubnetId}' \
  --output table || true

echo "[7] Terraform destroy"
terraform destroy -auto-approve
