# git-sync with Git LFS

Custom wrapper image that layers Git LFS tooling on top of the upstream `registry.k8s.io/git-sync/git-sync` release.

## Build & push

```bash
REGISTRY=ghcr.io/UDL-TF/git-sync-lfs
TAG=$(git rev-parse --short HEAD)

podman build -t "$REGISTRY:$TAG" -f containers/git-sync-lfs/Dockerfile .
podman push "$REGISTRY:$TAG"
# optionally tag latest
podman tag "$REGISTRY:$TAG" "$REGISTRY:latest"
podman push "$REGISTRY:latest"
```

Update the deployment to reference the pushed image, e.g. `ghcr.io/UDL-TF/git-sync-lfs:latest`.
