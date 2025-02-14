#!/bin/bash

# Exit on error with error trace
set -ex

# Default values
DEFAULT_TAG="latest"
PLATFORMS="linux/amd64,linux/arm64"
IMAGE_NAME="milka"
PROJECT_ID="milka-450720"

# Get the tag from command line argument or use default
TAG=${1:-$DEFAULT_TAG}

# Configure Docker to use GCP authentication
gcloud auth configure-docker

# Clean up Docker system
echo "Cleaning up Docker system..."
docker system prune -f
docker builder prune -f

# Clean up existing builder if exists
docker buildx rm milka-builder || true

# Create a new builder instance with more resources
docker buildx create --name milka-builder \
    --driver docker-container \
    --driver-opt network=host \
    --driver-opt env.DOCKER_CLI_EXPERIMENTAL=enabled \
    --buildkitd-flags '--allow-insecure-entitlement network.host --allow-insecure-entitlement security.insecure' \
    --use

# Start the builder with bootstrap
docker buildx inspect milka-builder --bootstrap

# Build and push the multi-platform image
echo "Building and pushing image for platforms: $PLATFORMS"
docker buildx build \
    --platform ${PLATFORMS} \
    --tag "gcr.io/${PROJECT_ID}/${IMAGE_NAME}:${TAG}" \
    --push \
    --memory=8g \
    --memory-swap=16g \
    --build-arg DOCKER_BUILDKIT=1 \
    --build-arg BUILDKIT_STEP_LOG_MAX_SIZE=10485760 \
    --build-arg PYTHONUNBUFFERED=1 \
    --build-arg PIP_NO_CACHE_DIR=1 \
    --build-arg CMAKE_BUILD_PARALLEL_LEVEL=4 \
    --progress=plain \
    --no-cache \
    -f Dockerfile \
    .

echo "Successfully built and pushed gcr.io/${PROJECT_ID}/${IMAGE_NAME}:${TAG}"
