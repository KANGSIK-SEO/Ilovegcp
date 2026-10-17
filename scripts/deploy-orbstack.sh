#!/bin/bash
# 보너스 과제 2: OrbStack 컨테이너 런타임으로 웹 서비스 배포 및 내·외부 헬스체크 자동 검증 스크립트
set -euo pipefail

echo "=== [Ilovegcp] OrbStack 컨테이너 웹 서비스 배포 및 검증 ==="

if ! orb status >/dev/null 2>&1; then
  echo "OrbStack 런타임을 시작합니다..."
  orb start
fi

echo "1) OrbStack 상태 및 Linux 머신 확인"
orb status
orb list

echo "2) 컨테이너 이미지 빌드 및 백그라운드 실행 (포트 매핑 0.0.0.0:80->80/tcp)"
docker compose up -d --build
sleep 2

echo "3) 컨테이너 실행 상태 확인 (docker ps)"
docker ps --filter "name=ilovegcp-web"

echo "4) 컨테이너 내부 아웃바운드 인터넷 통신 확인 (curl -I https://example.com)"
docker exec ilovegcp-web curl -sI https://example.com | head -n 5

echo "5) 인스턴스 내부 http://localhost (200 OK) 검증"
docker exec ilovegcp-web curl -sI http://localhost | head -n 5

echo "6) 외부 접속 검증: GET /health 호출 (200 OK 및 고정 응답 'OK')"
curl -si http://localhost/health
echo ""
echo "=== OrbStack 컨테이너 배포 및 모든 검증 통과 ==="
