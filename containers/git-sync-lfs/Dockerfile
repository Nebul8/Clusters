# syntax=docker/dockerfile:1.6

FROM registry.k8s.io/git-sync/git-sync:v4.5.1 AS git-sync

FROM alpine:3.20
RUN apk add --no-cache \
    ca-certificates \
    git \
    git-lfs \
    openssh-client \
    tzdata

COPY --from=git-sync /git-sync /usr/local/bin/git-sync
ENTRYPOINT ["/usr/local/bin/git-sync"]
