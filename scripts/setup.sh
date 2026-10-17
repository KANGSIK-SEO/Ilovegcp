#!/bin/bash
# GCP 웹 서비스 인프라 프로비저닝 스크립트 (서울 리전 asia-northeast3)
# 구성 요소: VPC(custom) -> Subnet(10.0.1.0/24) -> Route(0.0.0.0/0 -> default-igw)
#           -> Firewall Rules(tcp:80 전체, tcp:22 내 IP만) -> Static IP -> 최소권한 SA -> Compute Engine VM
set -euo pipefail

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || echo 'ks-work-7788')"
REGION="asia-northeast3"
ZONE="asia-northeast3-a"
VPC_NAME="mission-vpc"
SUBNET_NAME="mission-public-subnet"
SUBNET_RANGE="10.0.1.0/24"
INSTANCE_NAME="mission-web-server"
MACHINE_TYPE="e2-micro"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
SA_NAME="mission-deployer"
STATIC_IP_NAME="mission-static-ip"

MY_IP="$(curl -s https://api.ipify.org)/32"
echo "=== [Ilovegcp] GCP 인프라 구성을 시작합니다 ==="
echo "프로젝트 ID : $PROJECT_ID"
echo "리전 / 존   : $REGION / $ZONE"
echo "내 공인 IP  : $MY_IP (SSH 22번 포트 단독 허용)"

echo "1) VPC Network 생성 (custom subnet mode)"
gcloud compute networks create "$VPC_NAME" --subnet-mode=custom

echo "2) Public Subnet 생성 ($SUBNET_RANGE)"
gcloud compute networks subnets create "$SUBNET_NAME" \
  --network="$VPC_NAME" \
  --region="$REGION" \
  --range="$SUBNET_RANGE"

echo "3) 기본 인터넷 게이트웨이 라우트 확인 (0.0.0.0/0 -> default-internet-gateway)"
gcloud compute routes list --filter="network:$VPC_NAME"

echo "4) VPC Firewall Rules 생성 (HTTP 80은 0.0.0.0/0, SSH 22는 내 IP만 허용, 0-65535 전체허용 금지)"
gcloud compute firewall-rules create allow-http \
  --network="$VPC_NAME" \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=web-server

gcloud compute firewall-rules create allow-ssh-my-ip \
  --network="$VPC_NAME" \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges="$MY_IP" \
  --target-tags=web-server

echo "5) 고정 외부 IP 예약 (Elastic IP 대응)"
gcloud compute addresses create "$STATIC_IP_NAME" --region="$REGION"
STATIC_IP=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" --format="get(address)")
echo "예약된 고정 외부 IP: $STATIC_IP"

echo "6) IAM 최소권한 서비스 계정 생성 (Owner/Editor 및 Storage/SQL 권한 미부여)"
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="Mission Deployer (Least Privilege)" || true

for ROLE in "roles/compute.instanceAdmin.v1" "roles/compute.networkAdmin" "roles/iam.serviceAccountUser"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="$ROLE" \
    --condition=None
done

echo "7) Compute Engine VM 생성 (Ubuntu 22.04 LTS, 10GiB pd-balanced, Nginx & /health 구성)"
gcloud compute instances create "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --network="$VPC_NAME" \
  --subnet="$SUBNET_NAME" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=web-server \
  --address="$STATIC_IP" \
  --service-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --scopes="https://www.googleapis.com/auth/compute.readonly" \
  --metadata=startup-script='#!/bin/bash
apt-get update -y
apt-get install -y nginx curl
systemctl enable nginx
echo "OK" > /var/www/html/health
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location = /health {
        default_type text/plain;
        return 200 "OK\n";
    }
}
EOF
systemctl restart nginx
'

echo ""
echo "=== 프로비저닝 완료 ==="
echo "(A) 브라우저 접속 : http://${STATIC_IP}"
echo "(B) 헬스체크 호출 : curl -i http://${STATIC_IP}/health"
echo "SSH 접속 명령     : gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE}"
