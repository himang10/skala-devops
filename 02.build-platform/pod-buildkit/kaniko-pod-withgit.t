apiVersion: v1
kind: Pod
metadata:
  name: {{USER_NAME}}-buildkit-pod-springboot
  namespace: {{NAMESPACE}}
  labels:
    app: {{USER_NAME}}
spec:
  # Init Container: Maven 빌드
  initContainers:
  - name: build
    image: maven:3.8.5-openjdk-17
    workingDir: /workspace
    command: ["/bin/bash"]
    args:
      - -c
      - |
        echo "=== Git Clone 시작 ==="
        git clone https://{{GIT_USERNAME}}:{{GIT_PASSWORD}}@{{GIT_REPO_URL}} .
        echo "=== Maven 빌드 시작 ==="
        mvn clean install -DskipTests
        echo "=== 빌드 완료 ==="
        ls -al

    volumeMounts:
      - name: workspace
        mountPath: /workspace

  # Main Container: BuildKit 빌드
  containers:
  - name: buildkit
    image: moby/buildkit:rootless
    command: ["buildctl-daemonless.sh"]
    args:
      - build
      - --frontend=dockerfile.v0
      - --local=context=/workspace
      - --local=dockerfile=/workspace
      - --opt=platform=linux/arm64,linux/amd64
      - --output=type=image,name={{DOCKER_REGISTRY}}/{{USER_NAME}}-{{IMAGE_NAME}}:{{VERSION}}.spring-buildkit-kube,push=true
    env:
      - name: DOCKER_CONFIG
        value: /home/user/.docker
    securityContext:
      seccompProfile:
        type: Unconfined
    volumeMounts:
      - name: workspace
        mountPath: /workspace
      - name: buildkit-secret
        mountPath: /home/user/.docker
        readOnly: true

  restartPolicy: Never
  volumes:
    - name: workspace
      emptyDir: {}
    - name: buildkit-secret
      secret:
        secretName: harbor-registry-secret
        items:
          - key: .dockerconfigjson
            path: config.json
