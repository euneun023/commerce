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

# === 여기서부터 보완 코드 시작 ===
# === [3-1] 수정 버전 ===
echo "[3-1] Waiting for AWS Load Balancers to be fully deleted..."
while true; do
  # 해당 VPC에 연결된 로드밸런서들의 ARN 목록을 가져옵니다.
  LB_ARNS=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
    --output text)

  # 목록이 비어있으면(개수가 0이면) 루프 탈출
  if [ -z "$LB_ARNS" ]; then
    echo "All Load Balancers deleted successfully."
    break
  else
    # 개수를 세어서 출력
    LB_COUNT=$(echo "$LB_ARNS" | wc -w)
    echo "Still $LB_COUNT Load Balancer(s) remaining... checking again in 20s"
    sleep 20
  fi
done

echo "[3-2] Cleaning up orphaned ENIs"
# 노드가 삭제된 후에도 남아있는 ENI(Network Interface) 강제 정리 시도
ENI_IDS=$(aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=status,Values=available \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)

for ENI in $ENI_IDS; do
  echo "Deleting available ENI: $ENI"
  aws ec2 delete-network-interface --region "$AWS_REGION" --network-interface-id "$ENI" || true
done
# === 여기까지 보완 코드 끝 ===

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
