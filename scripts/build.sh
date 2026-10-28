#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

UPSTREAM_REPO="https://github.com/hashicorp/consul-template.git"
UPSTREAM_TAG="v0.43.1"
TEST_ONLY=false
CLEAN=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --tag <tag>     Upstream git tag to clone and build (default: ${UPSTREAM_TAG})
  --test-only     Run unit tests on patched code without compiling final binary
  --clean         Remove .build and bin directories before building
  -h, --help      Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            UPSTREAM_TAG="$2"
            shift 2
            ;;
        --test-only)
            TEST_ONLY=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

RELEASE_TAG="${UPSTREAM_TAG}-p.elburb"
BUILD_DIR="${REPO_ROOT}/.build/src-${UPSTREAM_TAG}"
BIN_DIR="${REPO_ROOT}/bin"

if [ "$CLEAN" = true ]; then
    echo "==> Cleaning build artifacts..."
    rm -rf "${REPO_ROOT}/.build" "${BIN_DIR}"
fi

mkdir -p "${REPO_ROOT}/.build" "${BIN_DIR}"

if [ ! -d "${BUILD_DIR}/.git" ]; then
    echo "==> Cloning ${UPSTREAM_REPO} at ${UPSTREAM_TAG}..."
    git clone --depth 1 --branch "${UPSTREAM_TAG}" "${UPSTREAM_REPO}" "${BUILD_DIR}"
else
    echo "==> Reusing cached upstream source at ${BUILD_DIR}..."
    cd "${BUILD_DIR}"
    git reset --hard HEAD
    git clean -fd
fi

cd "${BUILD_DIR}"

echo "==> Applying patches from ${REPO_ROOT}/patches..."
shopt -s nullglob
PATCH_FILES=("${REPO_ROOT}/patches"/*.patch)
if [ ${#PATCH_FILES[@]} -eq 0 ]; then
    echo "ERROR: No patch files found in ${REPO_ROOT}/patches" >&2
    exit 1
fi

for patch in "${PATCH_FILES[@]}"; do
    echo "    -> Applying $(basename "$patch")..."
    git apply "$patch"
done
shopt -u nullglob

if [ "$TEST_ONLY" = true ]; then
    echo "==> Running unit tests (config and template packages)..."
    go test -v ./config ./template
    echo "==> Tests passed successfully!"
    exit 0
fi

echo "==> Compiling static binary (linux/amd64)..."
GIT_COMMIT=$(git rev-parse --short HEAD || echo "patched")
OUTPUT_NAME="consul-template_${RELEASE_TAG}_linux_amd64"
OUTPUT_BIN="${BIN_DIR}/${OUTPUT_NAME}"

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -trimpath \
    -ldflags "-s -w -X github.com/hashicorp/consul-template/version.GitCommit=${GIT_COMMIT} -X github.com/hashicorp/consul-template/version.Version=${UPSTREAM_TAG}" \
    -o "${OUTPUT_BIN}" \
    .

# Create convenient symlink
ln -sf "${OUTPUT_NAME}" "${BIN_DIR}/consul-template"

# Generate sha256 checksum
cd "${BIN_DIR}"
sha256sum "${OUTPUT_NAME}" > "${OUTPUT_NAME}.sha256"

echo "==> Build complete!"
echo "    Binary:   ${OUTPUT_BIN}"
echo "    Symlink:  ${BIN_DIR}/consul-template"
echo "    Checksum: ${OUTPUT_BIN}.sha256"
"${OUTPUT_BIN}" -v
