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

for tgb in $(kubectl get targetgroupbinding -A -o name 2>/dev/null); do
  kubectl patch "$tgb" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
done

echo "[1-2] Delete traefik-specific resources"
kubectl delete svc traefik -n traefik --ignore-not-found=true --wait=false || true
kubectl delete targetgroupbinding --all -A --ignore-not-found=true --wait=false || true
kubectl delete ns traefik --ignore-not-found=true --wait=false || true

echo "[2] Delete Karpenter resources"
kubectl delete nodepool --all --ignore-not-found=true --wait=false || true
kubectl delete ec2nodeclass --all --ignore-not-found=true --wait=false || true

echo "[3] Uninstall Helm releases"
helm uninstall aws-load-balancer-controller -n kube-system --wait || true
helm uninstall karpenter -n kube-system --wait || true
helm uninstall argocd -n argocd --wait || true
helm uninstall traefik -n traefik --wait || true
helm uninstall cert-manager -n cert-manager --wait || true

echo "[3-1] Waiting for ELBv2 Load Balancers in VPC to disappear..."
while true; do
  LB_ARNS=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
    --output text 2>/dev/null || true)

  if [ -z "$LB_ARNS" ]; then
    echo "All ELBv2 Load Balancers deleted."
    break
  fi

  aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='$VPC_ID'].[LoadBalancerName,State.Code,DNSName]" \
    --output table || true
  sleep 20
done

echo "[3-2] Waiting for NAT Gateways in VPC to disappear..."
while true; do
  NAT_IDS=$(aws ec2 describe-nat-gateways \
    --region "$AWS_REGION" \
    --filter Name=vpc-id,Values="$VPC_ID" \
    --query "NatGateways[?State!='deleted'].NatGatewayId" \
    --output text 2>/dev/null || true)

  if [ -z "$NAT_IDS" ]; then
    echo "All NAT Gateways deleted."
    break
  fi

  aws ec2 describe-nat-gateways \
    --region "$AWS_REGION" \
    --filter Name=vpc-id,Values="$VPC_ID" \
    --query "NatGateways[?State!='deleted'].[NatGatewayId,State,SubnetId]" \
    --output table || true
  sleep 20
done

echo "[3-3] Check remaining network interfaces in VPC"
aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'NetworkInterfaces[*].{ENI:NetworkInterfaceId,Status:Status,Desc:Description,Subnet:SubnetId,PrivateIp:PrivateIpAddress,Attachment:Attachment.InstanceId}' \
  --output table || true

echo "[3-4] Delete orphaned AVAILABLE ENIs"
ENI_IDS=$(aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=status,Values=available \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' \
  --output text 2>/dev/null || true)

for ENI in $ENI_IDS; do
  echo "Deleting ENI: $ENI"
  aws ec2 delete-network-interface \
    --region "$AWS_REGION" \
    --network-interface-id "$ENI" || true
done

echo "[3-5] Check Elastic IPs still attached in VPC"
aws ec2 describe-addresses \
  --region "$AWS_REGION" \
  --query 'Addresses[*].{PublicIp:PublicIp,AllocationId:AllocationId,AssociationId:AssociationId,InstanceId:InstanceId,NetworkInterfaceId:NetworkInterfaceId}' \
  --output table || true

echo "[4] Extra wait for AWS cleanup"
sleep 90

echo "[5] Final dependency check"
echo "== LoadBalancers =="
aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].[LoadBalancerName,State.Code,DNSName]" \
  --output table || true

echo "== NAT Gateways =="
aws ec2 describe-nat-gateways \
  --region "$AWS_REGION" \
  --filter Name=vpc-id,Values="$VPC_ID" \
  --query "NatGateways[?State!='deleted'].[NatGatewayId,State,SubnetId]" \
  --output table || true

echo "== ENIs =="
aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'NetworkInterfaces[*].{ENI:NetworkInterfaceId,Status:Status,Desc:Description,Subnet:SubnetId}' \
  --output table || true

echo "== Subnets =="
aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'Subnets[*].{SubnetId:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone}' \
  --output table || true

echo "[6] Terraform destroy"
terraform destroy -auto-approve
