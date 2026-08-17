#!/usr/bin/env bash

set -euo pipefail

IMG_TAG=python-buildah

source "./load-properties.sh"

load_properties "../env.properties"

REGISTRY_SERVER=${DOCKER_REGISTRY%%/*}
IMAGE_REF="${DOCKER_REGISTRY}/${PROJECT_NAME}/${USER_NAME}-${IMAGE_NAME}:${VERSION}.${IMG_TAG}"

echo "Buildah 멀티 플랫폼 빌드 및 푸시: ${IMAGE_REF} (linux/arm64, linux/amd64)"
docker run --rm \
  -e REG_HOST="${REGISTRY_SERVER}" \
  -e REG_USER="${DOCKER_REGISTRY_USER}" \
  -e REG_PASS="${DOCKER_REGISTRY_PASSWORD}" \
  -e IMAGE_REF="${IMAGE_REF}" \
  -v "$(pwd):/workspace" \
  -w /workspace \
  --privileged \
  quay.io/buildah/stable:latest \
  bash -c '
    set -eux

    buildah bud --storage-driver=overlay \
      --platform linux/arm64,linux/amd64 \
      --manifest "${IMAGE_REF}" \
      .

    echo "[info] Login: ${REG_HOST}"
    buildah login -u "${REG_USER}" -p "${REG_PASS}" "${REG_HOST}"

    buildah manifest push --storage-driver=overlay \
      --all "${IMAGE_REF}" \
      "docker://${IMAGE_REF}"
  '
