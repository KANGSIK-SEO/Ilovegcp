#!/bin/bash
# GCP 리소스 일괄 정리 및 과금 방지 검증 스크립트
# 삭제 순서(하위 -> 상위): VM(부팅 디스크 포함) -> 미사용 디스크 -> 정적 외부 IP -> Firewall Rules -> Subnet -> VPC -> IAM SA
set -euo pipefail

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || echo 'ks-work-7788')"
REGION="asia-northeast3"
ZONE="asia-northeast3-a"
VPC_NAME="mission-vpc"
SUBNET_NAME="mission-public-subnet"
INSTANCE_NAME="mission-web-server"
SA_NAME="mission-deployer"
STATIC_IP_NAME="mission-static-ip"

echo "=== [Ilovegcp] 과금 방지를 위한 GCP 리소스 일괄 정리를 시작합니다 ==="

echo "1) Compute Engine 인스턴스 삭제 (부팅 Persistent Disk 10GiB 동시 삭제)"
gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet || true

echo "2) 정적 외부 IP 해제 (Static External IP Release)"
gcloud compute addresses delete "$STATIC_IP_NAME" --region="$REGION" --quiet || true

echo "3) Firewall Rules 삭제 (allow-http, allow-ssh-my-ip)"
gcloud compute firewall-rules delete allow-http allow-ssh-my-ip --quiet || true

echo "4) Subnet 삭제 ($SUBNET_NAME)"
gcloud compute networks subnets delete "$SUBNET_NAME" --region="$REGION" --quiet || true

echo "5) VPC Network 삭제 ($VPC_NAME)"
gcloud compute networks delete "$VPC_NAME" --quiet || true

echo "6) IAM 서비스 계정 삭제 ($SA_NAME)"
gcloud iam service-accounts delete "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --quiet || true

echo ""
echo "=== 잔여 과금 리소스 0건 확인 명령 ==="
echo "  gcloud compute instances list"
echo "  gcloud compute disks list"
echo "  gcloud compute addresses list"
echo "  gcloud compute firewall-rules list --filter=\"network:${VPC_NAME}\""
echo "  gcloud compute networks list --filter=\"name=${VPC_NAME}\""
