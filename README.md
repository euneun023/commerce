# commerce

Spring Boot 기반 커머스 API를 AWS EKS 위에 GitOps 방식으로 배포하는 DevOps 포트폴리오 프로젝트입니다.
애플리케이션 코드보다 **인프라 프로비저닝(Terraform) → CI/CD(GitHub Actions) → GitOps 배포(ArgoCD) → 관측(Prometheus/Grafana/Loki)** 로 이어지는 전체 파이프라인 구축에 초점을 두었습니다.

## 프로젝트 개요

- Spring Boot로 만든 간단한 커머스 API(상품 조회, 헬스체크, DB 체크, Redis 캐시)를 예제 워크로드로 사용하고, 그 주변의 인프라/배포/관측 체계를 직접 구축했습니다.
- `terraform/00-module`이 VPC, EKS, Karpenter, ArgoCD, cert-manager, Traefik, AWS Load Balancer Controller 등 클러스터와 애드온 전체를 프로비저닝합니다.
- 애플리케이션 배포는 GitHub Actions가 이미지를 빌드해 ECR에 푸시하고 Helm values 파일을 갱신하면, ArgoCD가 이를 감지해 자동 동기화하는 **GitOps 흐름**으로 구성했습니다.
- 모니터링/로깅(kube-prometheus-stack, Loki, Promtail, Slack 알림)과 k6 기반 부하테스트 환경(`load-test` 전용 네임스페이스)까지 별도로 구성해, 운영 관점의 장애 대응·튜닝 경험을 담았습니다.

## 기술 구성표

| 영역 | 기술 |
|---|---|
| Application | Java 17, Spring Boot 3.5.10, Spring Data JPA, Spring Cache(Redis), Spring Actuator + Micrometer(Prometheus), MariaDB JDBC |
| CI | GitHub Actions (`ci.yml`) — Gradle 빌드/테스트, Docker 빌드 검증 |
| CD | GitHub Actions (`cd.yml`) — Docker 이미지 빌드 → ECR 푸시 → Helm `values.yaml` 이미지 태그 자동 커밋 |
| Container | Docker multi-stage build (`eclipse-temurin:17-jdk`) |
| GitOps | ArgoCD (Helm 기반 Application 5종: commerce, commerce-load-test, monitoring, loki, promtail, redis) |
| IaC | Terraform (`terraform-aws-modules/eks` ~20.0, VPC 모듈, `helm_release` 리소스로 ArgoCD/cert-manager/Traefik/Karpenter/metrics-server 설치) |
| K8s 애드온 | Karpenter(오토스케일링), AWS Load Balancer Controller, metrics-server, EBS CSI Driver, cert-manager, Traefik |
| Ingress/TLS | Traefik IngressRoute + cert-manager `ClusterIssuer`(Let's Encrypt prod/staging) |
| Observability | kube-prometheus-stack(Prometheus/Grafana/Alertmanager), Loki + Promtail, 커스텀 `PrometheusRule`/`ServiceMonitor`, Alertmanager → Slack 알림 |
| Data | MariaDB(Bitnami 서브차트), Redis(bitnamilegacy) |
| 부하테스트 | k6 (`load-test/k6-ramp-test.js`), 전용 `load-test` 네임스페이스/HPA/PDB |

## 배포 흐름

1. **CI** (`.github/workflows/ci.yml`): `dev`, `feature/**` 브랜치 푸시 및 `dev`로의 PR에서 Gradle 빌드(`build -x test`)와 Docker 빌드 검증을 수행합니다(푸시는 하지 않음).
2. **CD** (`.github/workflows/cd.yml`): `dev`, `feature/health-db-v2` 브랜치 푸시 시
   - Gradle 빌드 → Docker 이미지 빌드 → `GITHUB_SHA` 앞 7자리를 태그로 ECR에 푸시
   - `sed`로 `helm-chart/commerce-api/values.yaml`의 `image.tag`를 새 태그로 치환
   - `github-actions[bot]` 계정으로 값 파일을 같은 브랜치에 커밋 후 `git push` (커밋 메시지에 `[skip ci]`를 붙이고, 워크플로우 자체도 `values.yaml` 변경은 트리거에서 제외해 무한 루프를 방지)
3. **GitOps 동기화**: ArgoCD(Terraform으로 설치, `argocd.tf`)가 `argocd/apps/helm/*.yaml`의 Application 매니페스트를 `automated: {prune: true, selfHeal: true}`로 계속 감시합니다. 2번 단계에서 `values.yaml`이 바뀌면 ArgoCD가 이를 감지해 Helm 차트를 재렌더링하고 EKS에 롤아웃합니다.
4. **인프라 레이어**: VPC/EKS/Karpenter/ALB Controller/cert-manager/Traefik/ArgoCD 자체는 GitHub Actions에 포함되지 않고 `terraform/00-module`을 통해 별도로(수동) `terraform apply` 합니다.
5. **인그레스/TLS**: Traefik `IngressRoute`(web → `redirect-https` 미들웨어, websecure → `api-ratelimit` 미들웨어)가 `commerce.dotory.site`로 들어오는 트래픽을 `api-svc`로 라우팅하고, cert-manager `ClusterIssuer`(`letsencrypt-prod`)가 HTTP-01 챌린지로 TLS 인증서를 발급합니다.

> 참고: 현재 `argocd/apps/helm/*.yaml`의 `targetRevision`은 `feature/health-db-v2`로 지정되어 있습니다. `main` 브랜치로 머지가 완료된 시점 기준으로는, ArgoCD가 `main`을 보도록 이 값을 갱신해 주는 것이 좋습니다.

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
└── docker-compose.yaml       # 로컬 개발용 MariaDB + API 컨테이너
```

## 트러블슈팅

커밋 히스토리에 남아 있는 실제 문제 해결 사례입니다.

**TLS / cert-manager**
- ACME 서버 URL과 필드명이 잘못되어 `ClusterIssuer` 인증서 발급이 실패 → URL/필드 수정 (`fix: correct ACME server URL and field names in ClusterIssuer`)
- Let's Encrypt staging 인증서로는 브라우저 신뢰가 안 되는 문제 → production 발급자(`letsencrypt-prod`)로 전환 (`feat: switch to production letsencrypt issuer`, `feat: switch cert-manager issuer to letsencrypt-prod for valid SSL`)
- IngressRoute의 포트와 TLS secret 이름이 실제 리소스와 불일치 → 포트를 80으로, TLS secret 이름을 일치시킴 (`fix: update IngressRoute port to 80 and align TLS secret name`)

**모니터링 / 알림 (Prometheus, Alertmanager, Slack)**
- `PrometheusRule` YAML 문법 오류로 룰이 로드되지 않음 → 두 차례에 걸쳐 문법 수정 (`fix: PrometheusRule 문법 오류 수정`, `수정2`)
- Alertmanager 라우팅에 매칭되지 않는 알림이 기본 리시버가 없어 오류 발생 → `null` 리시버 추가 (`fix(monitoring): add missing 'null' receiver to Alertmanager config`)
- Slack Webhook URL을 매니페스트에 직접 넣지 않고 Kubernetes Secret 파일에서 읽어오도록 변경 (`fix: configure Alertmanager Slack webhook from secret`, `fix: load Alertmanager Slack webhook from secret file`)
- ArgoCD의 기본 동기화 옵션으로 kube-prometheus-stack CRD 업데이트가 반영되지 않음 → `ServerSideApply` 옵션 활성화 (`fix: enable ServerSideApply for monitoring app`)
- Alertmanager 설정이 복잡해지며 문제 재현이 어려워짐 → 라우팅 설정 단순화 (`fix: simplify Alertmanager config`)

**로깅 (Loki / Promtail)**
- `loki-values.yaml`의 YAML 문법 오류 수정 (`fix: correct yaml syntax in loki-values.yaml`)
- Promtail의 파드 로그 경로 relabeling 설정이 잘못되어 로그 수집 실패 → relabel 규칙 수정 (`fix: correct promtail pod log path relabeling`)

**Redis**
- Redis persistence용 `storageClass`가 지정되지 않아 볼륨 프로비저닝 실패 → `gp3`로 명시 (`fix: set storageClass for redis persistence`)
- Bitnami의 Docker Hub 공식 이미지 배포 정책 변경으로 기존 이미지 태그를 pull할 수 없게 됨 → `bitnamilegacy` 리포지토리로 전환 (`fix: redis images to bitnamilegacy`)

**부하테스트 (k6 / load-test 차트)**
- Helm 헬퍼 템플릿 문법 오류로 차트 렌더링 실패 → 두 차례 수정 (`fix:helm helper template syntax`)
- 템플릿에서 값이 없을 때 nil pointer 오류 발생 → 방어 로직 추가 (`fix: resolve nil pointer error in load-test templates`)
- 부하테스트 시작 시 프로브 지연시간이 부족해 파드가 준비되기 전에 재시작됨 → `startupProbe`/probe 지연시간 증가 (`fix: increase startup probe delay for load test app`, `fix: increase probe delays for load test startup`)
- 부하테스트 중 HPA가 과도하게 늦게 반응 → CPU 임계값을 낮춤 (`lower hpa cpu threshold for load test`)
- 운영(prod) 리소스가 부하테스트 차트에도 함께 적용되는 문제 → load-test values에서 비활성화 (`fix: disable prod resources for load test chart`)

**인프라 (Terraform / EKS)**
- EKS 노드에서 사용하던 기존 AMI 계열의 지원 종료에 대응 → 노드 그룹을 AL2023으로 전환하고 `destroy-first.sh` 스크립트를 함께 보강 (`chore: switch EKS node group to AL2023 and harden destroy script`)
- AWS 계정 전환 후 기존 ECR 경로로 이미지를 pull할 수 없음 → 새 계정의 ECR 경로로 이미지 참조 수정 (`fix: update ecr image path to new account`)
- `dev` 브랜치와 병합 과정에서 `values.yaml`에 충돌 마커가 남는 문제가 반복 발생 → 충돌 정리 (`fix: remove git conflict markers in values.yaml`, `fix: resolve merge conflict in values.yaml`, `Fix: resolve merge conflict with dev branch`)
