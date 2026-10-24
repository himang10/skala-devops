#!/usr/bin/env bash
# 전체 흐름
#   1단계: env.properties 에서 Git 정보 및 이미지 정보 로드
#   2단계: 로컬 workspace 디렉터리 생성
#   3단계: maven 이미지(init-container 와 동일)로 git clone + mvn clean install
#   4단계: 빌드 결과 workspace 를 buildkit 이미지에 마운트하여 멀티플랫폼 빌드 및 푸시
#   5단계: Kustomize dev 이미지 태그 업데이트
#   6단계: Kubernetes 배포 및 롤아웃 확인
set -euo pipefail

IMAGE_NAME="webserver"
VERSION=1.0
IMG_TAG=buildkit

PROJECT_NAME=${CLASS_NAME}
USER_NAME=${STUDENT_NUM}

K8S_NAMESPACE=${CLASS_NAME}
DEPLOYMENT_NAME=${USER_NAME}-myfirst-api-server

source ./load-properties.sh

# ---------------------------------------------------------------------------
# 1단계: env.properties 로드 (GIT_*, IMAGE_NAME, VERSION, DOCKER_REGISTRY* 등)
# ---------------------------------------------------------------------------
step1_load_config() {
  echo "=== [1/6] 설정 로드: env.properties ==="
  load_properties ../../env.properties
}

# ---------------------------------------------------------------------------
# 2단계: 로컬 workspace 생성 (이전 결과는 삭제)
# ---------------------------------------------------------------------------
step2_prepare_workspace() {
  echo "=== [2/6] workspace 생성 ==="
  rm -rf "./workspace"
  mkdir -p "./workspace"
}

# ---------------------------------------------------------------------------
# 3단계: maven 컨테이너에서 git clone + maven 빌드 (workspace 마운트)
# ---------------------------------------------------------------------------
step3_git_clone_and_maven_build() {
  echo "=== [3/6] Git Clone + Maven 빌드 (maven:3.9-eclipse-temurin-21) ==="
  docker run --rm \
    -e GIT_USERNAME="${GIT_USERNAME}" \
    -e GIT_PASSWORD="${GIT_PASSWORD}" \
    -e GIT_REPO_URL="${GIT_REPO_URL}" \
    -e GIT_BRANCH="${GIT_BRANCH}" \
    -v "$(pwd)/workspace:/workspace" \
    -v ${HOME}/.m2:/root/.m2 \
    --workdir /workspace \
    maven:3.9-eclipse-temurin-21 \
    /bin/bash -c '
      set -eu
      echo "=== Git Clone 시작 ==="
      git clone -b "${GIT_BRANCH}" "https://${GIT_USERNAME}:${GIT_PASSWORD}@${GIT_REPO_URL}" .
      echo "=== Maven 빌드 시작 ==="
      mvn clean install -DskipTests
      echo "=== 빌드 완료 ==="
      ls -al
    '

    # target 디렉터리에 jar 파일이 없으면 종료
    if ! ls ./workspace/target/*.jar >/dev/null 2>&1; then
      echo "오류: ./workspace/target/ 에 jar 파일이 생성되지 않았습니다." >&2
      exit 1
    fi
    echo "jar 확인: $(ls ./workspace/target/*.jar)"
}

# ---------------------------------------------------------------------------
# 4단계: buildkit 컨테이너에서 이미지 빌드 및 레지스트리 푸시 (동일 workspace 마운트)
# ---------------------------------------------------------------------------
step4_buildkit_build_and_push() {
  # FINAL_IMAGE_TAG는 GIT 커밋 해시를 포함한 태그 (예: 1.0.buildkit-abcdef1)
  HASHCODE=$(git -C ./workspace rev-parse --short=7 HEAD)
  FINAL_IMAGE_TAG="${VERSION}.${IMG_TAG}-${HASHCODE}"

  echo "=== [4/6] BuildKit 멀티 플랫폼 빌드 및 푸시: ${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${FINAL_IMAGE_TAG} (linux/arm64, linux/amd64) ==="

  # 레지스트리 인증 설정 파일 생성
  mkdir -p ./auth
  cat > ./auth/config.json <<EOF
{
  "auths": {
    "${DOCKER_REGISTRY}": {
      "username": "${DOCKER_REGISTRY_USER}",
      "password": "${DOCKER_REGISTRY_PASSWORD}",
      "auth": "$(echo -n "${DOCKER_REGISTRY_USER}:${DOCKER_REGISTRY_PASSWORD}" | base64)"
    }
  }
}
EOF

  # 멀티 플랫폼 이미지 빌드 및 푸시
  docker run --rm \
    --privileged \
    --security-opt seccomp=unconfined \
    -e DOCKER_CONFIG=/home/user/.docker \
    -v "$(pwd)/workspace:/workspace:ro" \
    -v "$(pwd)/auth:/home/user/.docker:ro" \
    --entrypoint buildctl-daemonless.sh \
    moby/buildkit:latest \
      build \
      --frontend dockerfile.v0 \
      --local context=/workspace \
      --local dockerfile=/workspace \
      --opt platform=linux/arm64,linux/amd64 \
      --output "type=image,name=${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${FINAL_IMAGE_TAG},push=true"

  # 인증 파일 정리
  rm -rf ./auth
}

# ---------------------------------------------------------------------------
# 5단계: Kustomize dev overlay의 이미지 태그 업데이트
# ---------------------------------------------------------------------------
step5_update_kustomize_manifest() {
  echo "=== [5/6] Kustomize 이미지 태그 업데이트 ==="
  test -d ./kustomize/overlays/dev

  IMAGE_BASE="${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}"
  (
    cd ./kustomize/overlays/dev
    kustomize edit set image "${IMAGE_BASE}=${IMAGE_BASE}:${FINAL_IMAGE_TAG}"
  )
}

# ---------------------------------------------------------------------------
# 6단계: Kubernetes 배포 및 롤아웃 확인
# ---------------------------------------------------------------------------
step6_deploy_to_kubernetes() {
  echo "=== [6/6] Kubernetes 배포 ==="

  kustomize build ./kustomize/overlays/dev | kubectl apply -n "${K8S_NAMESPACE}" -f -
  kubectl rollout status "deployment/${DEPLOYMENT_NAME}" \
    -n "${K8S_NAMESPACE}" \
    --timeout=180s
  kubectl get pods -n "${K8S_NAMESPACE}" -l "app=${DEPLOYMENT_NAME}"
}

step1_load_config
step2_prepare_workspace
step3_git_clone_and_maven_build
step4_buildkit_build_and_push

# workdir을 workspace로 변경
cd ./workspace
step5_update_kustomize_manifest
step6_deploy_to_kubernetes
