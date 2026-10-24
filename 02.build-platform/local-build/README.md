# 로컬 컨테이너 이미지 빌드 & Push (CI) 실습

내 PC(Docker)에서 **소스 Clone → Maven 빌드 → 컨테이너 이미지 빌드 → 레지스트리 Push**까지의 CI 흐름을 실습합니다.
네 가지 빌드 도구(Docker buildx, Buildah, BuildKit, Kaniko)로 같은 결과물을 만들어 보고 차이를 비교합니다.

| 스크립트 | 빌드 도구 | 결과 이미지 태그 | 대상 플랫폼 |
|---|---|---|---|
| `01.build.push-withDocker.sh` | Docker buildx | `1.0.docker` | linux/arm64, linux/amd64 |
| `02.build.push-withBuildah.sh` | Buildah | `1.0.buildah` | linux/arm64, linux/amd64 |
| `03.build.push-withBuildkit.sh` | BuildKit (`buildctl-daemonless`) | `1.0.buildkit` | linux/arm64, linux/amd64 |
| `04.build.push-withKaniko.sh` | Kaniko | `1.0.kaniko` | linux/amd64 |

---

## 1. 실습 목적

- 소스 코드가 **컨테이너 이미지로 만들어져 레지스트리에 올라가는 과정(CI)** 을 단계별로 이해합니다.
- 빌드 환경을 로컬에 설치하지 않고 **컨테이너(Maven, Buildah, BuildKit, Kaniko)로 실행**하는 방법을 익힙니다.
- 빌드 도구별 동작 방식(데몬 유무, 인증 방식, 멀티 플랫폼 지원)의 차이를 비교합니다.
- 푸시한 이미지를 `skala-registry.skala-ai.com` 에서 직접 확인합니다.

## 2. 각 단계 세부 흐름

네 스크립트 모두 **1~3단계는 동일**하고, **4단계(이미지 빌드/Push)만 도구별로 다릅니다.**

```
[1] 설정 로드 → [2] workspace 생성 → [3] Git Clone + Maven 빌드 → [4] 이미지 빌드 & Push → Registry
```

| 단계 | 함수 | 역할 |
|---|---|---|
| 1 | `step1_load_config` | `../../env.properties`에서 `GIT_REPO_URL`, `GIT_BRANCH`, `GIT_USERNAME`, `GIT_PASSWORD`를 읽어 환경 변수로 등록합니다 <br> (`load-properties.sh`). |
| 2 | `step2_prepare_workspace` | `./workspace` 디렉터리를 비우고 새로 만듭니다. 이전 빌드 결과는 삭제됩니다. |
| 3 | `step3_git_clone_and_maven_build` | `maven:3.9-eclipse-temurin-21` 컨테이너에 `workspace`를 마운트한 뒤 `git clone` → `mvn clean install -DskipTests`를 실행합니다. <br> `./workspace/target/*.jar`가 없으면 즉시 종료합니다. |
| 4 | `step4_*_build_and_push` | `workspace`(소스 + Dockerfile + jar)를 빌드 컨텍스트로 이미지를 만들고 레지스트리에 Push합니다. |

이미지 이름은 다음 규칙으로 만들어집니다.

```
${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${VERSION}.${IMG_TAG}
예) skala-registry.skala-ai.com/class-0/sk01-webserver:1.0.docker
```

- `PROJECT_NAME` = `CLASS_NAME` (레지스트리 프로젝트 이름)
- `USER_NAME` = `STUDENT_NUM` (수강생 번호)
- `IMAGE_NAME` = `webserver`, `VERSION` = `1.0`
- `IMG_TAG` = 도구 이름 (`docker`, `buildah`, `buildkit`, `kaniko`) → 같은 레지스트리에 도구별로 구분되어 올라갑니다.

## 3. 최종 결과물 확인

스크립트가 성공하면 레지스트리에 이미지가 올라갑니다. 확인은 두 가지 방법으로 합니다.

**① SKALA Image Resgitsry에서 접속해서 자신의 이미지 확인하기**

1. `https://skala-registry.skala-ai.com` 에 접속해 로그인합니다.
2. **Projects → `<CLASS_NAME>`** 프로젝트를 엽니다. (예. class-0... class-10)
3. 저장소 `<STUDENT_NUM>-webserver` 를 선택합니다. (예. sk000-webserver )
4. Tag 목록에서 실행한 스크립트의 태그(`1.0.docker`, `1.0.buildah`, `1.0.buildkit`, `1.0.kaniko`)가 있는지 확인합니다.
5. 멀티 플랫폼 빌드(Docker, Buildah, BuildKit)는 `linux/amd64`, `linux/arm64` 두 아키텍처가 함께 보여야 합니다. Kaniko는 `linux/amd64`만 보입니다.

**② 명령어**

```bash
docker login ${DOCKER_REGISTRY} -u ${DOCKER_REGISTRY_USER}
docker buildx imagetools inspect \
  ${DOCKER_REGISTRY}/${CLASS_NAME}/${STUDENT_NUM}-webserver:1.0.docker
# Manifests 항목에 linux/amd64, linux/arm64 가 표시되면 정상
```

## 4. 실제 실습 방법

### 4-1. 실행 순서

`local-build` 디렉터리에서 실행합니다. (`./load-properties.sh`, `./workspace`를 상대 경로로 참조합니다.)

```bash
cd 02.build-platform/local-build

# ① Docker buildx
./01.build.push-withDocker.sh

# ② Buildah
./02.build.push-withBuildah.sh

# ③ BuildKit
./03.build.push-withBuildkit.sh

# ④ Kaniko
./04.build.push-withKaniko.sh
```

각 스크립트는 독립적으로 실행되며 실행할 때마다 `workspace`를 새로 만들므로 순서는 자유입니다.

### 4-2. 실습 후 결과 확인

1. 터미널 마지막에 오류 없이 종료되는지 확인합니다 (3단계의 `jar 확인:` 로그, 4단계의 push 완료 로그).
   local-build/workspace 내에 git clone을 통해 내려받은 myfirst-api-server 내에 <br> 
   ./target 아래에 .jar 파일 생성여부를 확인합니다. 
2. 위 **3. 최종 결과물 확인**대로 `skala-registry.skala-ai.com`에서 태그를 확인합니다.
3. 4개 스크립트를 모두 실행했다면 한 저장소에 `1.0.docker`, `1.0.buildah`, `1.0.buildkit`, `1.0.kaniko` 네 개의 태그가 보여야 합니다.


## 참고: 디렉터리 구성

```
local-build/
├── 01.build.push-withDocker.sh    # Docker buildx
├── 02.build.push-withBuildah.sh   # Buildah
├── 03.build.push-withBuildkit.sh  # BuildKit
├── 04.build.push-withKaniko.sh    # Kaniko
├── load-properties.sh             # env.properties 로더
└── workspace/                     # 실행 시 생성 (Git Clone + Maven 결과)
```
