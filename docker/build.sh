#!/bin/sh

IMAGE_NAME="idiomusdocker/chatwoot"

# Load .env variables (REQUIRED)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
  echo "✅ Loaded .env configuration"
else
  echo "❌ Arquivo .env não encontrado!"
  exit 1
fi

# Get the last version of the image from Docker Hub
LAST_VERSION=$(curl -s "https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags?page_size=100" \
  | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' \
  | cut -d':' -f2 | tr -d '"' \
  | grep -v latest \
  | sort -V | tail -n 1)

# Get the last chatwoot version
CHATWOOT_VERSION=$(curl -s "https://hub.docker.com/v2/repositories/chatwoot/chatwoot/tags?page_size=100" \
  | grep -oE '"name":"v[0-9]+\.[0-9]+\.[0-9]+"' \
  | cut -d':' -f2 | tr -d '"' \
  | grep -v latest \
  | sort -V | tail -n 1)

echo "🔍 Last version published on Docker Hub for ${IMAGE_NAME}: ${LAST_VERSION:-none found}"
echo "🔍 Last version published on Docker Hub for chatwoot: ${CHATWOOT_VERSION:-none found}"
echo "\n"
echo "📦 Enter the image version (e.g.: 1.0.0):"
read VERSION

echo "⚠️ You entered version: $VERSION. Confirm? (y/n)"
read CONFIRM

if [ "$CONFIRM" != "y" ]; then
  echo "❌ Operation cancelled."
  exit 1
fi

echo "➕ Do you also want to tag and push as 'latest'? (y/n)"
read PUSH_LATEST

# Set APP_VERSION (used for version detection - independent of Sentry)
APP_VERSION="production-${VERSION}"

echo "🚧 Building ${IMAGE_NAME}:${VERSION}..."
echo "📌 APP_VERSION: ${APP_VERSION}"

# Build the image
docker build \
  --no-cache \
  --platform linux/amd64 \
  --build-arg ENV=production \
  --build-arg RAILS_ENV=production \
	-f ./docker/Dockerfile \
  -t ${IMAGE_NAME}:${VERSION} .

if [ $? -ne 0 ]; then
  echo "❌ Error building the image. Aborting."
  exit 1
fi

# Tag as latest (if confirmed)
if [ "$PUSH_LATEST" = "y" ]; then
  docker tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:latest
fi

# Push the versioned image
echo "📤 Pushing ${IMAGE_NAME}:${VERSION}..."
docker push ${IMAGE_NAME}:${VERSION}

# Push the latest (if marked)
if [ "$PUSH_LATEST" = "y" ]; then
  echo "📤 Pushing ${IMAGE_NAME}:latest..."
  docker push ${IMAGE_NAME}:latest
fi

echo "✅ Process completed successfully!"
