# 로컬 빌드 & Kubernetes 배포 (CI + CD) 실습

내 PC(Docker)에서 **소스 Clone → Maven 빌드 → 컨테이너 이미지 빌드/Push → Kustomize 이미지 태그 갱신 → 내 네임스페이스에 배포 → 배포 확인**까지 한 번에 실습합니다.

이미지를 만들어 레지스트리에 올리는 앞부분(1~4단계, CI)은 [`02.build-platform/local-build`](../../02.build-platform/local-build/README.md)와 같고, <br>여기서는 **5~6단계(Kustomize 갱신 + Kubernetes 배포, CD)** 가 추가됩니다.

| 스크립트 | 빌드 도구 | 이미지 태그 예시 | 대상 플랫폼 |
|---|---|---|---|
| `01.build.deploy-withDocker.sh` | Docker buildx | `1.0.docker-0c28983` | linux/arm64, linux/amd64 |
| `02.build.deploy-withBuildah.sh` | Buildah | `1.0.buildah-0c28983` | linux/arm64, linux/amd64 |
| `03.build.deploy-withBuildkit.sh` | BuildKit (`buildctl-daemonless`) | `1.0.buildkit-0c28983` | linux/arm64, linux/amd64 |
| `04.build.deploy-withKaniko.sh` | Kaniko | `1.0.kaniko-0c28983` | linux/amd64 |

---

## 1. 실습 목적

- 소스 코드가 **이미지가 되어 레지스트리에 올라가고(CI), 내 네임스페이스의 Pod로 실행되는(CD)** 전체 흐름을 이해합니다.
- 이미지 태그에 **Git 커밋 해시(7자리)** 를 붙여, 빌드할 때마다 어떤 소스로 만든 이미지인지 추적하고 항상 새 이미지가 배포되도록 합니다.
- Kustomize로 **이미지 태그만 바꿔** 배포하는 방법을 익힙니다 (`kustomize edit set image`).
- 배포 결과를 `kubectl`로 단계별로 확인하는 방법을 익힙니다.

## 2. 각 단계 세부 흐름

```
[1] 설정 로드 → [2] workspace 생성 → [3] Git Clone + Maven 빌드
   → [4] 이미지 빌드 & Push(Registry) → [5] Kustomize 이미지 태그 갱신 → [6] Kubernetes 배포 & 롤아웃 확인
```

| 단계 | 함수 | 역할 |
|---|---|---|
| 1 | `step1_load_config` | `../../env.properties`에서 `GIT_REPO_URL`, `GIT_BRANCH`, `GIT_USERNAME`, `GIT_PASSWORD`를 읽어 환경 변수로 등록합니다. <br>배포 대상(`K8S_NAMESPACE`, `DEPLOYMENT_NAME`)은 스크립트 상단에서 `CLASS_NAME`, `STUDENT_NUM`으로 정해집니다. |
| 2 | `step2_prepare_workspace` | `./workspace`를 비우고 새로 만듭니다. |
| 3 | `step3_git_clone_and_maven_build` | `maven:3.9-eclipse-temurin-21` 컨테이너에서 `git clone` 후 `mvn clean install -DskipTests` 를 실행합니다. <br> `target/*.jar`가 없으면 즉시 종료합니다. |
| 4 | `step4_*_build_and_push` | `HASHCODE=$(git rev-parse --short=7 HEAD)`로 `FINAL_IMAGE_TAG=1.0.<도구>-<해시>`를 만들고, <br>선택한 도구로 이미지를 빌드해 레지스트리에 Push합니다. |
| 5 | `step5_update_kustomize_manifest` | `workspace/kustomize/overlays/dev`에서 `kustomize edit set image`로 <br>이미지 태그를 4단계의 `FINAL_IMAGE_TAG`로 바꿉니다. |
| 6 | `step6_deploy_to_kubernetes` | `kustomize build` 결과를 `kubectl apply -n <내 네임스페이스>`로 적용하고, <br> `rollout status`로 Pod가 Ready 될 때까지 기다린 뒤 Pod 목록을 출력합니다. |

5~6단계는 4단계에서 클론된 소스를 기준으로 해야 하므로, 스크립트는 4단계 이후 `cd ./workspace`로 이동해서 실행합니다.

### 배포 대상 (개별 네임스페이스)

| 항목 | 값 | 설명 |
|---|---|---|
| 네임스페이스 | `K8S_NAMESPACE=${CLASS_NAME}` | 수강생 반의 네임스페이스에 배포됩니다. (예: `class-0`) |
| Deployment / Service 이름 | `${STUDENT_NUM}-myfirst-api-server` | 수강생 번호가 이름에 들어가므로 같은 네임스페이스에서도 내 것만 갱신됩니다. <br>(예: `skala-myfirst-api-server`) |
| ConfigMap | `skala-backend-configmap` | dev overlay가 함께 만드는 Spring 설정입니다. |
| 이미지 | `${DOCKER_REGISTRY}/${CLASS_NAME}/${STUDENT_NUM}-webserver:<태그>` | 5단계에서 태그가 교체됩니다. |

> 같은 네임스페이스를 여러 수강생이 함께 쓰므로, **내 `STUDENT_NUM`이 들어간 리소스만** 확인·수정합니다. <br>다른 사람의 Deployment는 건드리지 않습니다.

## 3. 최종 결과물 확인

배포가 끝나면 다음 세 곳에서 결과를 확인합니다.

### ① 레지스트리 (`skala-registry.skala-ai.com`)

1. `https://skala-registry.skala-ai.com` 에 접속해 로그인합니다.
2. **Projects → `<CLASS_NAME>` → `<STUDENT_NUM>-webserver`** 를 엽니다.
3. Tag 목록에서 `1.0.<도구>-<커밋해시>` 태그가 새로 생겼는지 확인합니다. (예: `1.0.kaniko-0c28983`)

### ② 5단계 결과: Kustomize 이미지 태그 갱신

`workspace/kustomize/overlays/dev/kustomization.yaml`의 `images`가 새 태그로 바뀝니다.

```yaml
# 실행 전
images:
- name: skala-registry.skala-ai.com/class-0/skala-webserver
  newTag: "1.0"

# 실행 후 (kustomize edit set image)
images:
- name: skala-registry.skala-ai.com/class-0/skala-webserver
  newName: skala-registry.skala-ai.com/class-0/skala-webserver
  newTag: 1.0.kaniko-0c28983
```

`kustomize build`한 최종 YAML에도 같은 태그가 반영되어 **내 네임스페이스**로 지정됩니다.

```text
kind: ConfigMap   name: skala-backend-configmap       namespace: class-0
kind: Service     name: skala-myfirst-api-server      namespace: class-0
kind: Deployment  name: skala-myfirst-api-server      namespace: class-0
                  image: skala-registry.skala-ai.com/class-0/skala-webserver:1.0.kaniko-0c28983
```

### ③ 6단계 결과: Kubernetes 배포 확인

`kubectl apply` 출력 (처음 배포는 `created`, 재배포는 `configured` / `unchanged`):

```text
=== [6/6] Kubernetes 배포 ===
configmap/skala-backend-configmap unchanged
service/skala-myfirst-api-server unchanged
deployment.apps/skala-myfirst-api-server configured
Waiting for deployment "skala-myfirst-api-server" rollout to finish: 0 of 1 updated replicas are available...
deployment "skala-myfirst-api-server" successfully rolled out
NAME                                        READY   STATUS    RESTARTS   AGE
skala-myfirst-api-server-5b8c7d6f4d-x2k9p   1/1     Running   0          25s
```

`successfully rolled out` 과 Pod의 `1/1 Running` 이 보이면 배포 성공입니다.

> 위 출력의 Deployment `configured` 와 이미지 태그는 실제 환경에서 이 스크립트가 만드는 결과 형식이며, 이름·해시·AGE 값은 사람마다 다릅니다.

## 4. 실제 실습 방법

### 4-1. 실행 순서

`local-build-deploy` 디렉터리에서 실행합니다. (`./load-properties.sh`, `./workspace`를 상대 경로로 참조합니다.)

```bash
cd 03.kustomize/local-build-deploy

# ① Docker buildx
./01.build.deploy-withDocker.sh

# ② Buildah
./02.build.deploy-withBuildah.sh

# ③ BuildKit
./03.build.deploy-withBuildkit.sh

# ④ Kaniko
./04.build.deploy-withKaniko.sh
```

각 스크립트는 독립적이며 같은 Deployment를 갱신합니다. **마지막에 실행한 스크립트의 이미지가 현재 배포 이미지**가 됩니다.

### 4-2. 실습 후 결과 확인 (내 네임스페이스)

```bash
NS=${CLASS_NAME}
APP=${STUDENT_NUM}-myfirst-api-server

# 1) 배포 리소스 한눈에 보기
kubectl get deploy,svc,pods -n $NS -l app=$APP

# 2) 롤아웃 상태
kubectl rollout status deployment/$APP -n $NS

# 3) 실제로 배포된 이미지 태그 (방금 Push한 태그와 같아야 함)
kubectl get deploy $APP -n $NS \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# 4) 로그 확인
kubectl logs deploy/$APP -n $NS --tail=20

# 5) 배포 이력 (재배포할 때마다 revision 증가)
kubectl rollout history deployment/$APP -n $NS
```

예시 출력 (`NS=class-0`, `APP=skala-myfirst-api-server`):

```text
$ kubectl get deploy,svc,pods -n class-0 -l app=skala-myfirst-api-server
NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/skala-myfirst-api-server   1/1     1            1           2m

NAME                               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
service/skala-myfirst-api-server   ClusterIP   10.100.227.51   <none>        8080/TCP,8081/TCP   16d

NAME                                           READY   STATUS    RESTARTS   AGE
pod/skala-myfirst-api-server-5b8c7d6f4d-x2k9p  1/1     Running   0          2m

$ kubectl get deploy skala-myfirst-api-server -n class-0 -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
skala-registry.skala-ai.com/class-0/skala-webserver:1.0.kaniko-0c28983
```

레지스트리에 올라간 태그(`1.0.kaniko-0c28983`)와 `kubectl`의 이미지 태그가 **일치하면** 방금 만든 이미지가 그대로 배포된 것입니다.

배포 전에 클러스터 변경 없이 미리 확인하려면 서버 측 dry-run을 사용합니다.

```bash
kustomize build workspace/kustomize/overlays/dev | kubectl apply --dry-run=server -n ${CLASS_NAME} -f -
# configmap/skala-backend-configmap unchanged (server dry run)
# service/skala-myfirst-api-server configured (server dry run)
# deployment.apps/skala-myfirst-api-server configured (server dry run)
```

### 4-3. 문제 해결

| 증상 | 확인 / 원인 |
|---|---|
| `Missing kustomization file 'kustomization.yaml'` | 클론한 소스의 `kustomize/overlays/dev`에 `.yaml`이 없는 경우입니다. <br>소스 저장소에 렌더링된 YAML이 있는지 확인합니다. |
| `rollout status`가 timeout(180s) | `kubectl describe pod <pod> -n $NS`의 **Events**를 확인합니다. |
| Pod가 `Pending` | 노드 부족/taint가 흔한 원인입니다. 예: `FailedScheduling ... 2 node(s) had untolerated taint(s)` <br>— 클러스터의 스케줄링 문제이며 스크립트 문제가 아닙니다. |
| Pod가 `ImagePullBackOff` | 이미지 태그/레지스트리 주소가 맞는지, 클러스터에 레지스트리 pull secret이 있는지 확인합니다. |
| Push 중 `blob upload invalid` | 레지스트리의 일시적 오류입니다. 다시 실행하면 대부분 해결되며, Buildah 스크립트는 3회 자동 재시도합니다. |

## 참고: 디렉터리 구성

```
03.kustomize/
├── kustomize/                       # Kustomize base / overlays 원본 (*.t 템플릿 포함)
└── local-build-deploy/
    ├── 01.build.deploy-withDocker.sh
    ├── 02.build.deploy-withBuildah.sh
    ├── 03.build.deploy-withBuildkit.sh
    ├── 04.build.deploy-withKaniko.sh
    ├── load-properties.sh           # env.properties 로더
    └── workspace/                   # 실행 시 생성 (Git Clone + Maven 결과 + kustomize)
```
