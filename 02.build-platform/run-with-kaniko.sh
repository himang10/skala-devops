#!/bin/bash

IMG_TAG=python-kaniko

# 첫 번째 인자로 CPU 플랫폼 설정 (기본값: amd64)
if [ "${1:-}" = "arm64" ]; then
  CPU_PLATFORM=arm64
  IMG_TAG=${CPU_PLATFORM}-${IMG_TAG}
else
  CPU_PLATFORM=amd64
fi


SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=load-properties.sh
source "./load-properties.sh"

load_properties "../env.properties"

# 인증 설정 파일 생성
mkdir -p auth
cat > auth/config.json <<EOF
{
  "auths": {
    "skala-registry.skala-ai.com": {
      "username": "${DOCKER_REGISTRY_USER}",
      "password": "${DOCKER_REGISTRY_PASSWORD}",
      "auth": "$(echo -n "$DOCKER_REGISTRY_USER:$DOCKER_REGISTRY_PASSWORD" | base64)"
    }
  }
}
EOF

# 현재 디렉토리의 절대 경로 구하기
CURRENT_DIR=$(pwd)

# docker run으로 kaniko 실행
# gcr.io/kaniko-project/executor:latest \
docker run --rm \
  -v "${CURRENT_DIR}:/workspace" \
  -v "${CURRENT_DIR}/auth/config.json:/kaniko/.docker/config.json" \
  gcr.io/kaniko-project/executor:latest \
  --dockerfile=/workspace/Dockerfile \
  --context=dir:///workspace \
  --destination=${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${VERSION}.${IMG_TAG} \
  --custom-platform=linux/${CPU_PLATFORM}

# 정리
rm -rf auth
