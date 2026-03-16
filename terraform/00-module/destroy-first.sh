#!/bin/bash
set -euo pipefail

AWS_REGION="ap-northeast-2"
VPC_ID="vpc-xxxxxxxx"
CLUSTER_NAME="eks-mod"

echo "[1] Delete app ingress/service/deployment"
kubectl delete ingress --all -A --ignore-not-found=true || true
kubectl delete svc --all -A --ignore-not-found=true || true
kubectl delete deployment --all -A --ignore-not-found=true || true

echo "[2] Delete Karpenter resources"
kubectl delete nodepool --all --ignore-not-found=true || true
kubectl delete ec2nodeclass --all --ignore-not-found=true || true

echo "[3] Uninstall Helm releases"
helm uninstall aws-load-balancer-controller -n kube-system || true
helm uninstall karpenter -n kube-system || true
helm uninstall argocd -n argocd || true

echo "[4] Wait for AWS resources cleanup"
sleep 180

echo "[5] Check remaining Load Balancers"
aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[*].{Name:LoadBalancerName,VpcId:VpcId,State:State.Code}" \
  --output table || true

echo "[6] Check remaining ENIs in VPC"
aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'NetworkInterfaces[*].{ENI:NetworkInterfaceId,Desc:Description,Status:Status,Subnet:SubnetId}' \
  --output table || true

echo "[7] Terraform destroy"
terraform destroy -auto-approve
