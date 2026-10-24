#!/usr/bin/env bash
# 전체 흐름
#   1단계: env.properties 에서 Git 정보 및 이미지 정보 로드
#   2단계: 로컬 workspace 디렉터리 생성
#   3단계: maven 이미지(init-container 와 동일)로 git clone + mvn clean install
#   4단계: 빌드 결과 workspace 를 대상으로 docker buildx 멀티플랫폼 빌드 및 푸시
set -euo pipefail

IMAGE_NAME="webserver"
VERSION=1.0
IMG_TAG=docker

PROJECT_NAME=${CLASS_NAME}
USER_NAME=${STUDENT_NUM}

source ./load-properties.sh

# ---------------------------------------------------------------------------
# 1단계: env.properties 로드 (GIT_*, DOCKER_REGISTRY* 등)
# ---------------------------------------------------------------------------
step1_load_config() {
  echo "=== [1/4] 설정 로드: env.properties ==="
  load_properties ../../env.properties
}

# ---------------------------------------------------------------------------
# 2단계: 로컬 workspace 생성 (이전 결과는 삭제)
# ---------------------------------------------------------------------------
step2_prepare_workspace() {
  echo "=== [2/4] workspace 생성 ==="
  rm -rf "./workspace"
  mkdir -p "./workspace"
}

# ---------------------------------------------------------------------------
# 3단계: maven 컨테이너에서 git clone + maven 빌드 (workspace 마운트)
# ---------------------------------------------------------------------------
step3_git_clone_and_maven_build() {
  echo "=== [3/4] Git Clone + Maven 빌드 (maven:3.9-eclipse-temurin-21) ==="
  docker run --rm \
    -e GIT_USERNAME="${GIT_USERNAME}" \
    -e GIT_PASSWORD="${GIT_PASSWORD}" \
    -e GIT_REPO_URL="${GIT_REPO_URL}" \
    -e GIT_BRANCH="${GIT_BRANCH}" \
    -v "$(pwd)/workspace:/workspace" \
    -v "${HOME}/.m2:/root/.m2" \
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
# 4단계: docker buildx 로 멀티 플랫폼 이미지 빌드 및 레지스트리 푸시
# ---------------------------------------------------------------------------
step4_buildx_build_and_push() {
  echo "=== [4/4] Docker buildx 멀티 플랫폼 빌드 및 푸시: ${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${VERSION}.${IMG_TAG} (linux/arm64, linux/amd64) ==="

  # 레지스트리 로그인
  echo "[info] Login: ${DOCKER_REGISTRY}"
  echo "${DOCKER_REGISTRY_PASSWORD}" | docker login "${DOCKER_REGISTRY}" \
    -u "${DOCKER_REGISTRY_USER}" --password-stdin

  # 멀티 플랫폼 빌드 후 바로 푸시
  docker buildx build \
    --platform linux/arm64,linux/amd64 \
    -t "${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${VERSION}.${IMG_TAG}" \
    --push \
    ./workspace
}

step1_load_config
step2_prepare_workspace
step3_git_clone_and_maven_build
step4_buildx_build_and_push
