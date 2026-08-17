apiVersion: v1
kind: Pod
metadata:
  name: {{USER_NAME}}-buildkit-pod-python
  namespace: {{NAMESPACE}}
  labels:
    app: {{USER_NAME}}
spec:
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
        - --output=type=image,name={{DOCKER_REGISTRY}}/{{USER_NAME}}-{{IMAGE_NAME}}:{{VERSION}}.python-buildkit-kube,push=true
      env:
        - name: DOCKER_CONFIG
          value: /home/user/.docker
      securityContext:
        seccompProfile:
          type: Unconfined
      volumeMounts:
        - name: buildkit-secret
          mountPath: /home/user/.docker
        - name: workspace
          mountPath: /workspace
  restartPolicy: Never
  volumes:
    - name: buildkit-secret
      secret:
        secretName: harbor-registry-secret
        items:
          - key: .dockerconfigjson
            path: config.json
    - name: workspace
      configMap:   # 또는 PVC, emptyDir, gitRepo 등 원하는 소스로 교체 가능
        name: {{USER_NAME}}-app-workspace
