#!/usr/bin/env bash
# Builds/tests SpruceCore with ONLY the shared sources plus one module's Core folder,
# in an isolated temp copy. Lets several modules be developed in parallel without
# breaking each other's Linux builds.
#   ./scripts/test-core-module.sh Cleanup
set -euo pipefail
cd "$(dirname "$0")/.."
MODULE="${1:?usage: test-core-module.sh <Module>}"
shift || true
IMAGE="${SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.1-noble}"
TMP="$(mktemp -d /tmp/spruce-mod-$MODULE-XXXX)"
mkdir -p "$TMP/Sources/SpruceCore" "$TMP/Tests/SpruceCoreTests"
cp Package.swift "$TMP/"
cp -R Sources/SpruceCore/Shared "$TMP/Sources/SpruceCore/"
[ -d "Sources/SpruceCore/$MODULE" ] && cp -R "Sources/SpruceCore/$MODULE" "$TMP/Sources/SpruceCore/"
cp Tests/SpruceCoreTests/SharedTests.swift "$TMP/Tests/SpruceCoreTests/"
[ -d "Tests/SpruceCoreTests/$MODULE" ] && cp -R "Tests/SpruceCoreTests/$MODULE" "$TMP/Tests/SpruceCoreTests/"
pgrep dockerd >/dev/null || (nohup dockerd >/tmp/dockerd.log 2>&1 &) ; for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
docker run --rm -v "$TMP":/src -w /src "$IMAGE" \
  bash -c "swift build 2>&1 | grep -E 'error|Build complete' ; swift test $* 2>&1 | grep -E 'error|failed|Executed' | tail -40"
rm -rf "$TMP"
