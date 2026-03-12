#!/bin/bash
set -e

echo "[1/4] Destroy ArgoCD Helm release"
terraform destroy -target=helm_release.argocd -auto-approve

echo "[2/4] Destroy AWS Load Balancer Controller"
terraform destroy -target=helm_release.aws_load_balancer_controller -auto-approve

echo "[3/4] Destroy Kubernetes StorageClass"
terraform destroy -target=kubernetes_storage_class.gp3 -auto-approve

echo "[4/4] Waiting for AWS LB cleanup..."
sleep 120

echo "[5/5] Destroy remaining infrastructure"
terraform destroy -auto-approve
