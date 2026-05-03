#!/usr/bin/env bash
# Build da imagem Docker e push para o Magalu Cloud Container Registry (MCR).
#
# Pré-requisitos: Docker logado no MCR (ou defina MGC_REGISTRY_USER + MGC_REGISTRY_TOKEN).
#
# Variáveis (export ou arquivo .env ao lado do script):
#   MGC_REGION          br-se1 | br-ne1 (padrão: br-se1)
#   MGC_REGISTRY        nome do registry no MCR (obrigatório), ex.: meu-projeto-cr
#   MGC_REPOSITORY      nome do repositório/imagem (padrão: i-diario)
#   MGC_IMAGE_TAG       tag da imagem (padrão: short git SHA ou "latest")
#   DOCKERFILE          caminho do Dockerfile relativo à raiz (padrão: Dockerfile.production)
#   MGC_SKIP_LOGIN      se 1, não executa docker login
#   MGC_REGISTRY_USER   usuário do registry (login não-interativo)
#   MGC_REGISTRY_TOKEN  senha/token (--password-stdin)
#
# Uso:
#   ./docker/build-push-registry.sh
#   MGC_REGISTRY=meu-cr MGC_REPOSITORY=idiario-app ./docker/build-push-registry.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f "${BASH_SOURCE[0]%/*}/.env.registry" ]]; then
  # shellcheck source=/dev/null
  source "${BASH_SOURCE[0]%/*}/.env.registry"
fi

MGC_REGION="${MGC_REGION:-br-se1}"
MGC_REGISTRY="${MGC_REGISTRY:-}"
MGC_REPOSITORY="${MGC_REPOSITORY:-i-diario}"
MGC_IMAGE_TAG="${MGC_IMAGE_TAG:-}"
DOCKERFILE="${DOCKERFILE:-Dockerfile.production}"
MGC_SKIP_LOGIN="${MGC_SKIP_LOGIN:-0}"

if [[ "$MGC_REGION" != "br-se1" && "$MGC_REGION" != "br-ne1" ]]; then
  echo "MGC_REGION deve ser br-se1 ou br-ne1 (recebido: $MGC_REGION)" >&2
  exit 1
fi

if [[ -z "$MGC_REGISTRY" ]]; then
  echo "Defina MGC_REGISTRY com o nome do seu Container Registry na Magalu Cloud." >&2
  echo "Ex.: export MGC_REGISTRY=meu-projeto-cr" >&2
  exit 1
fi

if [[ -z "$MGC_IMAGE_TAG" ]]; then
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    MGC_IMAGE_TAG="$(git rev-parse --short HEAD)"
  else
    MGC_IMAGE_TAG="latest"
  fi
fi

REGISTRY_HOST="container-registry.${MGC_REGION}.magalu.cloud"
LOGIN_URL="https://${REGISTRY_HOST}"
IMAGE_REF="${REGISTRY_HOST}/${MGC_REGISTRY}/${MGC_REPOSITORY}:${MGC_IMAGE_TAG}"

echo "==> Registry: $LOGIN_URL"
echo "==> Imagem:   $IMAGE_REF"
echo "==> Contexto: $ROOT"
echo "==> Dockerfile: $DOCKERFILE"

if [[ "$MGC_SKIP_LOGIN" != "1" ]]; then
  if [[ -n "${MGC_REGISTRY_USER:-}" && -n "${MGC_REGISTRY_TOKEN:-}" ]]; then
    echo "==> docker login (não interativo)"
    printf '%s' "$MGC_REGISTRY_TOKEN" | docker login "$LOGIN_URL" -u "$MGC_REGISTRY_USER" --password-stdin
  else
    echo "==> docker login (interativo; defina MGC_REGISTRY_USER e MGC_REGISTRY_TOKEN para CI)"
    docker login "$LOGIN_URL"
  fi
fi

echo "==> docker build"
docker build -f "$DOCKERFILE" -t "$IMAGE_REF" "$ROOT"

echo "==> docker push"
docker push "$IMAGE_REF"

echo "==> Concluído: $IMAGE_REF"
