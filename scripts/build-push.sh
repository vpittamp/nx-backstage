#!/usr/bin/env bash
set -euo pipefail

# ========== Configuration ==========
REGISTRY_HOST="gitea.cnoe.localtest.me:8443"
REGISTRY_OWNER="giteaadmin"
IMAGE_NAME="backstage"
KARGO_WAREHOUSE="backstage"
KARGO_NAMESPACE="kargo-pipelines"

# ========== Parse Arguments ==========
VERSION=""
TRIGGER_KARGO=false
SKIP_BUILD=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] VERSION

Build and push Backstage Docker image to Gitea OCI registry.

Arguments:
  VERSION                 Version tag for the image (e.g., 1.0.0, latest)

Options:
  --trigger-kargo         Trigger Kargo warehouse refresh after push
  --skip-build            Skip yarn build, only build Docker image
  --registry HOST         Registry host (default: $REGISTRY_HOST)
  --owner OWNER           Registry owner (default: $REGISTRY_OWNER)
  --image NAME            Image name (default: $IMAGE_NAME)
  --warehouse NAME        Kargo warehouse name (default: $KARGO_WAREHOUSE)
  --namespace NS          Kargo namespace (default: $KARGO_NAMESPACE)
  -h, --help              Show this help message

Examples:
  $(basename "$0") 1.0.0
  $(basename "$0") --trigger-kargo 1.0.0
  $(basename "$0") --skip-build --trigger-kargo latest
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --trigger-kargo) TRIGGER_KARGO=true; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --registry) REGISTRY_HOST="$2"; shift 2 ;;
        --owner) REGISTRY_OWNER="$2"; shift 2 ;;
        --image) IMAGE_NAME="$2"; shift 2 ;;
        --warehouse) KARGO_WAREHOUSE="$2"; shift 2 ;;
        --namespace) KARGO_NAMESPACE="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Error: Unknown option: $1" >&2; exit 1 ;;
        *) VERSION="$1"; shift ;;
    esac
done

# Validate version
if [[ -z "$VERSION" ]]; then
    echo "Error: VERSION is required" >&2
    echo "Run '$(basename "$0") --help' for usage" >&2
    exit 1
fi

# Full image reference
FULL_IMAGE="${REGISTRY_HOST}/${REGISTRY_OWNER}/${IMAGE_NAME}:${VERSION}"

echo "============================================"
echo "Build and Push Backstage"
echo "============================================"
echo "Version:    $VERSION"
echo "Image:      $FULL_IMAGE"
echo "Kargo:      $TRIGGER_KARGO"
echo "============================================"

# ========== Build Backend ==========
if [[ "$SKIP_BUILD" == "false" ]]; then
    echo ""
    echo ">>> Building TypeScript..."
    yarn tsc

    echo ""
    echo ">>> Building backend bundle..."
    yarn build:backend
else
    echo ""
    echo ">>> Skipping build (--skip-build)"
fi

# ========== Build Docker Image ==========
echo ""
echo ">>> Building Docker image..."
docker image build . \
    -f packages/backend/Dockerfile \
    --tag "${IMAGE_NAME}:${VERSION}" \
    --tag "$FULL_IMAGE"

# ========== Login to Registry ==========
echo ""
echo ">>> Logging into Gitea registry..."
if command -v idpbuilder &> /dev/null; then
    idpbuilder get secrets -p gitea -o json | \
        jq '.[0].password' -r | \
        docker login -u giteaAdmin --password-stdin "$REGISTRY_HOST"
else
    echo "Note: idpbuilder not found, assuming already logged in or using docker credentials"
    docker login "$REGISTRY_HOST" 2>/dev/null || true
fi

# ========== Push Image ==========
echo ""
echo ">>> Pushing image to $FULL_IMAGE..."
docker push "$FULL_IMAGE"

echo ""
echo ">>> Image pushed successfully!"
echo "    $FULL_IMAGE"

# ========== Trigger Kargo ==========
if [[ "$TRIGGER_KARGO" == "true" ]]; then
    echo ""
    echo ">>> Triggering Kargo warehouse refresh..."

    if ! command -v kargo &> /dev/null; then
        echo "Error: kargo CLI not found" >&2
        echo "Install kargo CLI or trigger manually:" >&2
        echo "  kargo refresh warehouse $KARGO_WAREHOUSE -n $KARGO_NAMESPACE" >&2
        exit 1
    fi

    kargo refresh warehouse "$KARGO_WAREHOUSE" -n "$KARGO_NAMESPACE"

    echo ">>> Kargo warehouse refresh triggered"
    echo "    Warehouse: $KARGO_WAREHOUSE"
    echo "    Namespace: $KARGO_NAMESPACE"
fi

echo ""
echo "============================================"
echo "Done!"
echo "============================================"
