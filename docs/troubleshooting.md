# 트러블슈팅 보고서 (Troubleshooting Report)

클라우드 네트워크·보안·OrbStack Linux VM 배포 실습 과정에서 발생한 **3건의 실제 통신 및 권한 오류**에 대해 `증상 → 가설 → 검증 → 조치 → 결과 → 재발방지` 절차로 분석·해결한 기록입니다.

---

## 사례 1: 방화벽 SSH 소스 IP(`/32`) 불일치로 인한 SSH 접속 타임아웃

| 항목 | 상세 내용 |
|---|---|
| **증상 (문제 상황)** | Compute Engine VM(`mission-web-server`) 생성 직후 `gcloud compute ssh mission-web-server --zone=asia-northeast3-a` 실행 시 `ssh: connect to host 34.64.178.42 port 22: Operation timed out` 오류가 발생하며 접속 불가 |
| **원인 가설** | 1. VM 인스턴스가 아직 부팅 중이거나 `sshd` 데몬이 내려가 있음<br>2. VPC 방화벽 규칙(`allow-ssh-my-ip`)에 등록된 허용 CIDR(`sourceRanges`)과 현재 클라이언트 PC의 실제 공인 IP가 일치하지 않음<br>3. VM에 방화벽 타깃 네트워크 태그(`web-server`)가 누락됨 |
| **검증 방법** | 1. 방화벽 규칙 조회: `gcloud compute firewall-rules describe allow-ssh-my-ip --format="yaml(sourceRanges,targetTags,allowed)"` 실행 결과 기존 테스트 대역(`203.0.113.10/32`)이 들어가 있음을 확인<br>2. 현재 내 공인 IP 확인: `curl -s https://api.ipify.org` (또는 `curl -s ifconfig.me`) 실행 결과 실제 공인 IP는 `121.135.181.35`임을 확인 |
| **조치 내용** | `allow-ssh-my-ip` 방화벽 규칙의 소스 범위를 현재 공인 IP 단일 호스트(`121.135.181.35/32`)로 즉시 갱신:<br>`gcloud compute firewall-rules update allow-ssh-my-ip --source-ranges="121.135.181.35/32"` |
| **결과** | `gcloud compute ssh mission-web-server --zone=asia-northeast3-a` 재실행 시 22번 포트로 즉시 핸드셰이크가 성립하며 정상 로그인 성공 |
| **재발 방지** | 1. 수동으로 IP를 하드코딩하지 않도록 `scripts/setup.sh` 내부에서 `MY_IP="$(curl -s https://api.ipify.org)/32"`로 실행 시점의 공인 IP를 자동 주입하도록 스크립트화<br>2. 유동 IP 환경에서 작업 위치가 바뀔 때를 대비해 배포 전 체크리스트에 `curl ifconfig.me` 대조 단계 추가 |

### 검증 및 조치 로그 근거
```bash
$ gcloud compute firewall-rules describe allow-ssh-my-ip --format="yaml(sourceRanges,targetTags)"
sourceRanges:
- 203.0.113.10/32
targetTags:
- web-server

$ curl -s ifconfig.me
121.135.181.35

$ gcloud compute firewall-rules update allow-ssh-my-ip --source-ranges="121.135.181.35/32"
Updated [https://www.googleapis.com/compute/v1/projects/ks-work-7788/global/firewalls/allow-ssh-my-ip].
```

---

## 사례 2: 네트워크 태그(`web-server`) 누락 및 Nginx `default` 설정 충돌로 인한 외부 접속 오류

| 항목 | 상세 내용 |
|---|---|
| **증상 (문제 상황)** | 인스턴스 내부에서 `curl http://localhost`는 응답하나, 외부에서 `http://34.64.178.42/health` 호출 시 타임아웃이 발생하거나 커스텀 `/health` 응답(`OK`) 대신 기본 페이지/404가 반환됨 |
| **원인 가설** | 1. **클라우드 방화벽 계층**: GCP 방화벽 규칙(`allow-http`)은 `target-tags=web-server`가 지정되어 있으나, VM 인스턴스에 `web-server` 태그가 누락되어 인바운드 80번 패킷이 VPC 레벨에서 차단됨<br>2. **웹 서버 설정 계층**: Ubuntu 패키지(`apt-get install nginx`) 설치 시 자동 생성되는 `/etc/nginx/sites-enabled/default`가 `default_server`를 선점하여 `/etc/nginx/conf.d/ilovegcp.conf`의 `/health` 라우팅이 무시됨 |
| **검증 방법** | 1. VM 태그 확인: `gcloud compute instances describe mission-web-server --zone=asia-northeast3-a --format="get(tags.items)"` 실행 결과 빈 값 출력 확인<br>2. Nginx 활성 설정 및 소켓 확인: `orb -u root nginx -T` 및 `orb -u root ss -tlnp \| grep :80` 점검 |
| **조치 내용** | 1. VM 인스턴스에 `web-server` 네트워크 태그 추가:<br>`gcloud compute instances add-tags mission-web-server --zone=asia-northeast3-a --tags=web-server`<br>2. `/etc/nginx/sites-enabled/default` 심볼릭 링크를 제거하고 `ilovegcp.conf`(`0.0.0.0:80 default_server`)만 활성화한 뒤 `systemctl restart nginx` 실행 |
| **결과** | 외부에서 `http://34.64.178.42`(및 `http://analysis.orb.local`) 브라우저 접속 시 대시보드 정상 표시, `GET /health` 호출 시 `HTTP/1.1 200 OK` 및 `"OK"` 응답 확인 |
| **재발 방지** | 1. AWS Security Group과 달리 GCP는 **Firewall Rule의 `target-tags`와 VM의 `tags` 문자열이 정확히 일치해야 동작**하므로 `scripts/setup.sh`에 `--tags=web-server` 옵션을 고정<br>2. `scripts/deploy-orbstack.sh`에 `rm -f /etc/nginx/sites-enabled/default` 및 내·외부 `/health` 자동 검증 포함 |

### 검증 및 조치 로그 근거
```bash
$ gcloud compute instances add-tags mission-web-server --zone=asia-northeast3-a --tags=web-server
Updated [https://www.googleapis.com/compute/v1/projects/ks-work-7788/zones/asia-northeast3-a/instances/mission-web-server].

$ orb -u root bash -c "rm -f /etc/nginx/sites-enabled/default && systemctl restart nginx"
$ curl -i http://analysis.orb.local/health
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Content-Type: text/plain
Content-Length: 3

OK
```

---

## 사례 3: IAM 최소권한 적용 시 `iam.serviceAccounts.actAs` 누락 오류 해결 및 권한 격리 검증

| 항목 | 상세 내용 |
|---|---|
| **증상 (문제 상황)** | 관리자 권한(`Owner`/`Editor`)을 제거하고 `roles/compute.instanceAdmin.v1`만 부여한 배포용 계정으로 VM 생성 시 `Permission 'iam.serviceAccounts.actAs' denied` 오류 발생 |
| **원인 가설** | Compute Engine 인스턴스를 생성할 때 서비스 계정을 연결하려면 `compute.instanceAdmin.v1` 외에 해당 서비스 계정을 대리 실행할 수 있는 `roles/iam.serviceAccountUser` 권한이 추가로 필요함 |
| **검증 방법** | 1. GCP 오류 메시지의 필요 권한(`iam.serviceAccounts.actAs`) 확인<br>2. `gcloud projects get-iam-policy ks-work-7788 --flatten="bindings[].members" --filter="bindings.members:mission-deployer"`로 부여된 역할 목록 조회 |
| **조치 내용** | `Owner`/`Editor` 같은 과도한 권한을 부여하지 않고, 필요한 최소 역할 조합(`roles/compute.instanceAdmin.v1`, `roles/compute.networkAdmin`, `roles/iam.serviceAccountUser`)만 선별 부여. 실습과 무관한 Cloud Storage(`gsutil ls`) 호출 시 `AccessDeniedException: 403`으로 정상 차단됨을 함께 검증 |
| **결과** | 최소권한 원칙(Least Privilege)을 유지하면서 VPC·방화벽·VM 프로비저닝에 성공하고, 무관한 스토리지/DB 리소스 접근은 완벽히 차단됨 |
| **재발 방지** | IAM 설계 시 무조건 상위 기본 역할(`Owner`/`Editor`)을 부여하는 관행을 금지하고, 오류 로그에 명시된 단일 권한(`actAs`)에 대응하는 사전 정의 역할만 점진적으로 추가하는 최소권한 프로비저닝 절차 수립 |
