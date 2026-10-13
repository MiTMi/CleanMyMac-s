#!/usr/bin/env bash
# Builds and tests SpruceCore on Linux inside the official Swift Docker image.
# Usage: ./scripts/test-core-linux.sh [extra swift test args, e.g. --filter CleanupTests]
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE="${SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.1-noble}"
# Unique build dir per checkout so parallel worktrees don't collide.
BUILD_DIR="/tmp/spruce-build-$(pwd | md5sum | cut -c1-8)"
pgrep dockerd >/dev/null || (nohup dockerd >/tmp/dockerd.log 2>&1 &) ; for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
docker run --rm -v "$PWD":/src -v "$BUILD_DIR":/build -w /src "$IMAGE" \
  bash -c "swift build --build-path /build 2>&1 | grep -E 'error|warning: (var|initialization)|Compiling|Build complete' ; swift test --build-path /build $* 2>&1 | grep -E 'error|failed|Executed|passed' | tail -40"
