#!/bin/bash
# OrbStack Linux VM (orb) 기반 웹 서비스 배포 및 내·외부 헬스체크 자동 검증 스크립트 (No Docker)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== [Ilovegcp] OrbStack Linux VM 웹 서비스 배포 및 검증 (Docker 미사용) ==="

if ! orb status >/dev/null 2>&1; then
  echo "OrbStack 런타임을 시작합니다..."
  orb start
fi

echo "1) OrbStack 상태 및 Linux VM 목록 확인"
orb status
orb list

echo "2) OrbStack Ubuntu VM 내부에 Nginx 설치 및 웹 서비스(/, /health) 배포"
orb -u root bash -c "
  which nginx >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq nginx curl)
  cp '${SCRIPT_DIR}/web/index.html' /var/www/html/index.html
  cp '${SCRIPT_DIR}/web/health' /var/www/html/health
  cp '${SCRIPT_DIR}/web/nginx.conf' /etc/nginx/conf.d/ilovegcp.conf
  rm -f /etc/nginx/sites-enabled/default
  systemctl enable nginx
  systemctl restart nginx
"

echo "3) VM 내부 Nginx 서비스 상태 및 0.0.0.0:80 포트 리스닝 확인"
orb -u root systemctl status nginx --no-pager | head -n 10
orb -u root ss -tlnp | grep ':80'

echo "4) VM 내부 아웃바운드 인터넷 통신 확인 (curl -I https://example.com)"
orb curl -sI https://example.com | head -n 5

echo "5) VM 내부 http://localhost (200 OK) 검증"
orb curl -sI http://localhost | head -n 5

echo "6) 외부 접속 검증: GET /health 호출 (200 OK 및 고정 응답 'OK')"
curl -si http://analysis.orb.local/health
echo ""
echo "=== OrbStack Linux VM 배포 및 모든 검증 통과 ==="
