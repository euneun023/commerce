# commerce

Spring Boot 기반 커머스 API를 AWS EKS 위에 GitOps 방식으로 배포하는 DevOps 포트폴리오 프로젝트입니다.
애플리케이션 코드보다 **인프라 프로비저닝(Terraform) → CI/CD(GitHub Actions) → GitOps 배포(ArgoCD) → 관측(Prometheus/Grafana/Loki)** 로 이어지는 전체 파이프라인 구축에 초점을 두었습니다.

## 프로젝트 개요

- Spring Boot로 만든 간단한 커머스 API(상품 조회, 헬스체크, DB 체크, Redis 캐시)를 예제 워크로드로 사용하고, 그 주변의 인프라/배포/관측 체계를 직접 구축했습니다.
- `terraform/00-module`이 VPC, EKS, Karpenter, ArgoCD, cert-manager, Traefik, AWS Load Balancer Controller 등 클러스터와 애드온 전체를 프로비저닝합니다.
- 애플리케이션 배포는 GitHub Actions가 이미지를 빌드해 ECR에 푸시하고 Helm values 파일을 갱신하면, ArgoCD가 이를 감지해 자동 동기화하는 **GitOps 흐름**으로 구성했습니다.
- 모니터링/로깅(kube-prometheus-stack, Loki, Promtail, Slack 알림)과 k6 기반 부하테스트 환경(`load-test` 전용 네임스페이스)까지 별도로 구성해, 운영 관점의 장애 대응·튜닝 경험을 담았습니다.
- 최근에는 운영 구조 재정비, Secret 관리 구조 정리, GitOps 배포 기준 브랜치 정리 작업을 진행했습니다.

## 기술 구성표

| 영역 | 기술 |
|---|---|
| Application | Java 17, Spring Boot 3.5.10, Spring Data JPA, Spring Cache(Redis), Spring Actuator + Micrometer(Prometheus), MariaDB JDBC |
| CI | GitHub Actions (`ci.yml`) — Gradle 빌드/테스트, Docker 빌드 검증 |
| CD | GitHub Actions (`cd.yml`) — Docker 이미지 빌드 → ECR 푸시 → Helm `values.yaml` 이미지 태그 자동 커밋 |
| Container | Docker multi-stage build (`eclipse-temurin:17-jdk`) |
| GitOps | ArgoCD (Helm 기반 Application 6종: commerce, commerce-load-test, monitoring, loki, promtail, redis) |
| IaC | Terraform (`terraform-aws-modules/eks` ~20.0, VPC 모듈, `helm_release` 리소스로 ArgoCD/cert-manager/Traefik/Karpenter/metrics-server 설치) |
| K8s 애드온 | Karpenter(오토스케일링), AWS Load Balancer Controller, metrics-server, EBS CSI Driver, cert-manager, Traefik |
| Ingress/TLS | Traefik IngressRoute + cert-manager `ClusterIssuer`(Let's Encrypt prod/staging) |
| Observability | kube-prometheus-stack(Prometheus/Grafana/Alertmanager), Loki + Promtail, 커스텀 `PrometheusRule`/`ServiceMonitor`, Alertmanager → Slack 알림 |
| Data | MariaDB(Bitnami 서브차트 25.0.6), Redis(bitnamilegacy, 19.6.4) |
| 부하테스트 | k6 부하테스트 스크립트(`load-test/k6-ramp-test.js`), 전용 `load-test` 네임스페이스/HPA/PDB |

## 배포 흐름

1. **CI** (`.github/workflows/ci.yml`): `dev`, `feature/**` 브랜치 푸시 및 `dev`로의 PR에서 Gradle 빌드(`build -x test`)와 Docker 빌드 검증을 수행합니다(푸시는 하지 않음).
2. **CD** (`.github/workflows/cd.yml`): `dev`, `main` 브랜치 푸시 시
   - Gradle 빌드 → Docker 이미지 빌드 → `GITHUB_SHA` 앞 7자리를 태그로 ECR에 푸시
   - `sed`로 `helm-chart/commerce-api/values.yaml`의 `image.tag`를 새 태그로 치환
   - `github-actions[bot]` 계정으로 값 파일을 같은 브랜치에 커밋 후 `git push` (커밋 메시지에 `[skip ci]`를 붙이고, 워크플로우 자체도 `values.yaml` 변경은 트리거에서 제외해 무한 루프를 방지)
3. **GitOps 동기화**: ArgoCD(Terraform으로 설치, `argocd.tf`)가 `argocd/apps/helm/*.yaml`의 Application 매니페스트를 `automated: {prune: true, selfHeal: true}`로 계속 감시합니다. 2번 단계에서 `values.yaml`이 바뀌면 ArgoCD가 이를 감지해 Helm 차트를 재렌더링하고 EKS에 롤아웃합니다.
4. **인프라 레이어**: VPC/EKS/Karpenter/ALB Controller/cert-manager/Traefik/ArgoCD 자체는 GitHub Actions에 포함되지 않고 `terraform/00-module`을 통해 별도로(수동) `terraform apply` 합니다.
5. **인그레스/TLS**: Traefik `IngressRoute`(web → `redirect-https` 미들웨어, websecure → `api-ratelimit` 미들웨어)가 `commerce.dotory.site`로 들어오는 트래픽을 `api-svc`로 라우팅하고, cert-manager `ClusterIssuer`(`letsencrypt-prod`)가 HTTP-01 챌린지로 TLS 인증서를 발급합니다.

## Secret 관리

Helm chart에 평문 비밀번호를 두지 않고, 클러스터에 미리 만들어 둔 Kubernetes Secret을 `existingSecret`으로 참조하는 구조입니다. Bitnami MariaDB/Redis, kube-prometheus-stack(Grafana)는 각각 `existingSecret` 관련 필드명이 달라 실제 사용 중인 chart 버전의 values를 확인해서 맞췄습니다.

### MariaDB (Bitnami MariaDB 25.0.6)

- Secret: `commerce-db-secret` (namespace: `commerce`)
- key: `mariadb-root-password` (`auth.existingSecret` 사용 시 root password key 이름은 chart에서 고정)

```bash
kubectl create secret generic commerce-db-secret \
  --namespace commerce \
  --from-literal=mariadb-root-password=<YOUR_PASSWORD_HERE>
```

### Redis (Bitnami Redis 19.6.4)

- Secret: `commerce-redis-secret` (namespace: `commerce`)
- key: `redis-password` (`auth.existingSecretPasswordKey`로 key 이름 지정)

```bash
kubectl create secret generic commerce-redis-secret \
  --namespace commerce \
  --from-literal=redis-password=<YOUR_PASSWORD_HERE>
```

### Grafana (kube-prometheus-stack)

- Secret: `grafana-admin-secret` (namespace: `monitoring`)
- keys: `admin-user`, `admin-password`

```bash
kubectl create secret generic grafana-admin-secret \
  --namespace monitoring \
  --from-literal=admin-user=<YOUR_ADMIN_USERNAME> \
  --from-literal=admin-password=<YOUR_PASSWORD_HERE>
```

Kubernetes Secret은 namespace-scoped 리소스입니다. Spring Boot API와 Redis가 같은 `commerce` namespace에 있어, `commerce-redis-secret` 하나를 API와 Redis 양쪽에서 함께 참조합니다.

> `commerce-load-test` Application을 함께 배포하는 경우, `load-test` namespace에 별도의 DB Secret이 필요합니다.

```bash
kubectl create secret generic load-test-db-secret \
  --namespace load-test \
  --from-literal=mariadb-root-password=<YOUR_PASSWORD_HERE>
```

## 로컬 개발

`docker-compose.yaml`은 MariaDB + Spring Boot API 컨테이너만 구성되어 있습니다(Redis는 포함되어 있지 않습니다).

1. `.env.example`을 `.env`로 복사
2. `.env`에 `MARIADB_ROOT_PASSWORD` 값 입력
3. `docker compose up` 실행

`docker-compose.yaml`에서는 이 값을 아래 두 곳에 동일하게 전달합니다.

- MariaDB 컨테이너의 `MYSQL_ROOT_PASSWORD`
- Spring Boot API의 `SPRING_DATASOURCE_PASSWORD` (API가 MariaDB에 root로 접속하는 구조라 같은 값을 사용합니다)

## 디렉토리 구조

```
.
├── .github/workflows/       # CI(ci.yml), CD(cd.yml) — GitHub Actions
├── src/main/java/...        # Spring Boot 애플리케이션 (Controller/Service/Repository/설정)
├── terraform/
│   ├── 00-module/           # 실제 사용 중인 IaC: VPC/EKS/Karpenter/ArgoCD/cert-manager/Traefik 모듈 구성
│   └── 01-no-module/        # 모듈화 이전의 초기 버전(EKS/VPC를 모듈 없이 직접 정의)
├── helm-chart/
│   ├── commerce-api/        # 애플리케이션 Helm 차트 (mariadb 서브차트 포함, values.yaml/values.dev.yaml/values.prod.yaml/values.load-test.yaml)
│   └── monitoring/          # 모니터링용 values
├── argocd/
│   ├── apps/helm/           # ArgoCD Application 정의 (commerce, commerce-load-test, monitoring, loki, promtail, redis)
│   └── values/              # 각 Application이 참조하는 Helm values
├── clusterissuers/          # cert-manager ClusterIssuer(prod/staging)
├── karpenter/               # NodePool, EC2NodeClass 등 Karpenter 리소스
├── load-test/               # k6 부하테스트 스크립트와 전용 네임스페이스/워크로드 매니페스트
├── Dockerfile                # 3-stage 빌드(build → test → run)
├── docker-compose.yaml       # 로컬 개발용 MariaDB + API 컨테이너
└── .env.example              # 로컬 개발용 환경변수 예시
```

## 실행 방법

현재 bootstrap 과정에서 namespace 생성, Secret 생성, ArgoCD Application 등록은 수동 단계로 남아 있습니다.

### Local

`.env.example` → `.env` → `docker compose up` (자세한 내용은 위 [로컬 개발](#로컬-개발) 참고)

### AWS / EKS

1. `terraform/00-module`에서 `terraform apply`
   - EKS, VPC, Karpenter, ArgoCD, cert-manager, Traefik 등 기반 인프라 구성
2. Application이 사용할 namespace 사전 생성
   ```bash
   kubectl create namespace commerce
   kubectl create namespace monitoring
   kubectl create namespace logging
   kubectl create namespace load-test
   ```
3. [Secret 관리](#secret-관리)의 명령으로 기본 Secret 3종과 load-test DB Secret 생성 (`commerce-db-secret`, `commerce-redis-secret` → `commerce`, `grafana-admin-secret` → `monitoring`, `load-test-db-secret` → `load-test`)
4. `argocd/apps/helm/*.yaml`의 Application 6개 등록
   ```bash
   kubectl apply -f argocd/apps/helm/
   ```
5. ArgoCD가 각 Application을 sync하며 배포 (namespace와 Secret이 이미 준비되어 있어 정상적으로 기동됩니다)

## 트러블슈팅

커밋 히스토리와 실제 운영 중 겪은 문제 해결 사례입니다.

**1. Karpenter가 생성한 EC2가 Node로 등록되지 않음**

- 부하 테스트 중 기존 Node가 `Too many pods` 상태가 되어 Karpenter가 새 EC2를 생성했으나, 해당 EC2가 Kubernetes Node로 등록되지 않음
- IAM/access entry를 먼저 확인했으나 이상 없음 → EC2 console log에서 network interface(`ens5`)가 configuring 상태에 머무르는 것을 확인
- EC2 생성 성공과 Node registration 성공이 별개 단계임을 확인하고, 원인 확인 범위를 Karpenter 설정에서 private subnet 네트워크 경로 쪽으로 좁힘
- 해결까지 검증하지는 못했고, 네트워크 경로로 원인 범위를 좁힌 상태입니다.

**2. Pod Pending / `Too many pods`**

- Node의 CPU/메모리는 여유가 있는데도 `Too many pods` 이벤트 발생
- EKS는 instance type과 ENI 구성에 따라 Node당 스케줄 가능한 Pod 수(`maxPods`)가 제한됨을 확인
- instance type과 kubelet `maxPods` 설정을 조정

**3. HPA는 동작하지만 Node는 확장되지 않음**

- HPA로 Pod replica는 늘어나는데 Karpenter가 새 Node를 만들지 않음
- Karpenter는 실제 CPU 사용률이 아니라 Pod의 `resource requests` 기준으로 스케줄 가능 여부를 판단한다는 점을 확인
- requests가 낮게 설정되어 있어 기존 Node에도 배치 가능하다고 판단된 것이 원인 → requests를 실제 사용량에 맞게 조정

**4. Prometheus Target DOWN**

- `/actuator/prometheus` scrape가 실패
- 배포된 Docker 이미지와 최신 애플리케이션 코드가 일치하지 않음을 확인
- image tag를 수정

**5. `terraform destroy` 시 VPC/Subnet 삭제 실패**

- Kubernetes controller(AWS Load Balancer Controller)가 생성한 NLB/ENI 등 AWS 리소스가 Terraform state 밖에 남아 있어 VPC/Subnet 삭제가 막힘
- Terraform이 관리하는 리소스와 Kubernetes controller가 직접 만든 AWS 리소스를 구분
- Kubernetes 리소스 정리 → Kubernetes controller가 만든 AWS 리소스 제거 확인 → `terraform destroy` 순서로 teardown 흐름을 `destroy-first.sh`에 구성

**6. Helm provider v3 문법 변경 + ALB webhook readiness**

- ArgoCD 설치 과정에서 실패 발생
- AWS Load Balancer Controller의 webhook Service는 생성되었지만 endpoint가 아직 준비되지 않은 상태였음을 확인
- 리소스가 Created 상태인 것과 Ready 상태인 것이 같은 의미가 아님을 확인
- `depends_on`, `wait`, `timeout`으로 `helm_release.argocd`가 `aws_load_balancer_controller` 이후, 준비 완료까지 기다리도록 순서를 보장

**기타 개선 사례**

- ACME 서버 URL/필드명 오류로 `ClusterIssuer` 인증서 발급 실패 → 수정, 이후 Let's Encrypt staging → production(`letsencrypt-prod`) 전환
- IngressRoute의 포트/TLS secret 이름이 실제 리소스와 불일치 → 정정
- `PrometheusRule`/`loki-values.yaml` YAML 문법 오류 → 수정
- Alertmanager 라우팅에 매칭되지 않는 알림에 대한 기본 리시버 부재 → `null` 리시버 추가, 이후 라우팅 단순화
- Slack Webhook URL을 매니페스트에 직접 넣지 않고 Secret 파일에서 읽도록 변경
- ArgoCD 기본 동기화 옵션으로 CRD 업데이트가 반영되지 않음 → `ServerSideApply` 옵션 활성화
- Promtail의 로그 경로 relabeling 설정 오류 → 수정
- Redis persistence `storageClass` 미지정으로 볼륨 프로비저닝 실패 → `gp3`로 명시
- Bitnami의 Docker Hub 이미지 배포 정책 변경으로 기존 태그 pull 불가 → `bitnamilegacy` 리포지토리로 전환
- load-test Helm 차트의 템플릿 문법 오류, nil pointer 오류, 프로브 지연시간 부족, HPA 반응 지연, prod 리소스 값 혼입 등을 수정
- EKS 노드 AMI 계열 지원 종료에 대응해 AL2023으로 전환
- AWS 계정 전환 후 기존 ECR 경로로 이미지를 pull할 수 없음 → 새 계정 ECR 경로로 수정
- `dev` 브랜치 병합 과정에서 `values.yaml`에 conflict marker가 반복적으로 남는 문제 → 정리

## 한계 및 다음 개선 방향

- **Terraform state**: 현재 local state 구조로 진행했습니다. 협업 환경에서는 state 공유·유실·동시 수정 문제를 관리하기 위해 remote backend와 locking 구조를 적용할 수 있습니다.
- **ArgoCD bootstrap**: 현재 namespace 생성, Secret 생성, Application 등록 중 일부가 수동 단계로 남아 있습니다. 향후 이 bootstrap 과정을 자동화해 초기 구축 절차를 줄일 수 있습니다.
