#!/usr/bin/env bash
# Build da imagem Docker e push para o Magalu Cloud Container Registry (MCR).
#
# Pré-requisitos: Docker logado no MCR
#
# Variáveis (export ou arquivo .env ao lado do script):
#   MGC_IMAGE_TAG       tag da imagem (padrão: short git SHA ou "latest")
#
# Uso:
#   ./docker/build-push-registry.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f "${BASH_SOURCE[0]%/*}/.env.registry" ]]; then
  # shellcheck source=/dev/null
  source "${BASH_SOURCE[0]%/*}/.env.registry"
fi

MGC_IMAGE_TAG="${MGC_IMAGE_TAG:-}"

if [[ -z "$MGC_IMAGE_TAG" ]]; then
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    MGC_IMAGE_TAG="$(git rev-parse --short HEAD)"
  else
    MGC_IMAGE_TAG="latest"
  fi
fi

IMAGE_REF="container-registry.br-ne1.magalu.cloud/idiario/idiario-app:${MGC_IMAGE_TAG}"

echo "==> Imagem:   $IMAGE_REF"
echo "==> Contexto: $ROOT"

export DOCKER_BUILDKIT=1

CACHE_FROM="${MGC_CACHE_FROM:-container-registry.br-ne1.magalu.cloud/idiario/idiario-app:latest}"
docker pull "$CACHE_FROM" 2>/dev/null || true

echo "==> docker build (BuildKit + cache-from)"
docker build \
  -f "Dockerfile.production" \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --cache-from "$CACHE_FROM" \
  -t "$IMAGE_REF" \
  "$ROOT"

echo "==> docker push"
docker push "$IMAGE_REF"

echo "==> Concluído: $IMAGE_REF"
