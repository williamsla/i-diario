#!/usr/bin/env bash
#
# Deploy zero-downtime blue/green para o i-diário.
#
# Uso:
#   ./docker/deploy-zero-downtime.sh <nova-tag>
#
# O script detecta qual slot (blue ou green) está ativo, sobe o outro com a
# nova imagem, espera ficar saudável, chaveia o Nginx e derruba o antigo.

set -euo pipefail

NEW_TAG="${1:?Uso: $0 <nova-tag>}"
COMPOSE_FILE="docker-compose.production.yml"
ENV_FILE=".env.production"
NGINX_CONF="docker/nginx.conf"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_DIR"

COMPOSE="docker compose -f $COMPOSE_FILE --env-file $ENV_FILE"

current_upstream() {
  grep -oP 'set \$backend \Kapp-(blue|green)' "$NGINX_CONF" | head -1
}

wait_healthy() {
  local container="$1"
  local timeout="${2:-600}"
  echo "  Aguardando $container ficar saudável (timeout ${timeout}s)..."
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
    case "$status" in
      healthy)
        echo "  $container está saudável!"
        return 0
        ;;
      unhealthy)
        echo "  ERRO: $container ficou unhealthy."
        docker logs --tail 30 "$container"
        return 1
        ;;
    esac
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "  ERRO: timeout esperando $container."
  return 1
}

ACTIVE_SLOT=$(current_upstream)
if [ "$ACTIVE_SLOT" = "app-blue" ]; then
  NEW_SLOT="app-green"
  NEW_CONTAINER="idiario-app-green"
  OLD_CONTAINER="idiario-app-blue"
  PROFILE_ARG="--profile green"
else
  NEW_SLOT="app-blue"
  NEW_CONTAINER="idiario-app-blue"
  OLD_CONTAINER="idiario-app-green"
  PROFILE_ARG=""
fi

echo "==> Slot ativo: $ACTIVE_SLOT"
echo "==> Novo slot:  $NEW_SLOT (tag: $NEW_TAG)"

echo ""
echo "==> 1/5 Puxando nova imagem..."
docker pull "container-registry.br-ne1.magalu.cloud/idiario/idiario-app:${NEW_TAG}"

echo ""
echo "==> 2/5 Subindo $NEW_SLOT com tag $NEW_TAG..."
TAG="$NEW_TAG" $COMPOSE $PROFILE_ARG up -d --no-deps "$NEW_SLOT"

echo ""
echo "==> 3/5 Aguardando health check..."
if ! wait_healthy "$NEW_CONTAINER" 600; then
  echo "  FALHA! Derrubando $NEW_SLOT e mantendo $ACTIVE_SLOT."
  $COMPOSE $PROFILE_ARG stop "$NEW_SLOT"
  exit 1
fi

echo ""
echo "==> 4/5 Chaveando Nginx para $NEW_SLOT..."
sed -i "s/set \$backend ${ACTIVE_SLOT}/set \$backend ${NEW_SLOT}/" "$NGINX_CONF"

docker restart idiario-nginx-prod
sleep 2

# Verifica se o Nginx está apontando para o slot correto
INSIDE=$(docker exec idiario-nginx-prod grep -o "app-\(blue\|green\)" /etc/nginx/conf.d/default.conf | head -1)
if [ "$INSIDE" != "$NEW_SLOT" ]; then
  echo "  ERRO: Nginx não carregou o novo config (esperado=$NEW_SLOT, atual=$INSIDE). Revertendo..."
  sed -i "s/set \$backend ${NEW_SLOT}/set \$backend ${ACTIVE_SLOT}/" "$NGINX_CONF"
  docker restart idiario-nginx-prod
  exit 1
fi
echo "  Nginx chaveado para $NEW_SLOT."

echo ""
echo "==> 5/5 Parando slot antigo ($ACTIVE_SLOT) e atualizando Sidekiq..."

docker stop "$OLD_CONTAINER" && docker rm "$OLD_CONTAINER" 2>/dev/null || true

TAG="$NEW_TAG" $COMPOSE up -d --no-deps sidekiq

echo ""
echo "==> Deploy concluído! Ativo: $NEW_SLOT (tag: $NEW_TAG)"

# Atualiza TAG no .env.production para próximos comandos
if [ -f "$ENV_FILE" ]; then
  if grep -q "^TAG=" "$ENV_FILE"; then
    sed -i "s/^TAG=.*/TAG=${NEW_TAG}/" "$ENV_FILE"
  else
    echo "TAG=${NEW_TAG}" >> "$ENV_FILE"
  fi
  echo "==> TAG atualizada em $ENV_FILE"
fi
