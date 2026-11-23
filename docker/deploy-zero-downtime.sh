#!/usr/bin/env bash
#
# Deploy zero-downtime blue/green para o i-diário.
#
# Uso:
#   ./docker/deploy-zero-downtime.sh <nova-tag>
#
# O script detecta qual slot (blue ou green) está ativo, sobe o outro com a
# nova imagem, espera ficar saudável, recarrega o Nginx e derruba o antigo.
#
# A troca de slot grava o nginx.conf no mesmo inode e manda `nginx -s reload`.
# `sed -i` + `docker restart` derruba a porta publicada por alguns segundos.
# O container antigo só recebe SIGTERM depois que os workers velhos do Nginx
# terminam os pedidos que já tinham aceitado.

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

# Grava no inode atual. `sed -i` renomeia o arquivo; o bind mount do container
# continua no inode antigo e só passa a enxergar a troca se o Nginx reiniciar.
write_backend() {
  local from="$1"
  local to="$2"
  local tmp
  tmp="$(mktemp)"
  sed "s/set \$backend ${from}/set \$backend ${to}/" "$NGINX_CONF" > "$tmp"
  if ! grep -q "set \$backend ${to}" "$tmp"; then
    echo "  ERRO: não foi possível apontar o Nginx para ${to}."
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp" > "$NGINX_CONF"
  rm -f "$tmp"
}

reload_nginx() {
  docker exec idiario-nginx-prod nginx -t
  docker exec idiario-nginx-prod nginx -s reload
}

nginx_upstream_inside() {
  docker exec idiario-nginx-prod grep -o "app-\(blue\|green\)" /etc/nginx/conf.d/default.conf | head -1
}

# Workers atuais, antes do reload. No reload eles recebem SIGQUIT, fecham
# conexão ociosa e só saem quando o pedido que já estava aberto termina.
nginx_worker_pids() {
  docker exec idiario-nginx-prod sh -c '
    for cmd in /proc/[0-9]*/cmdline; do
      [ -r "$cmd" ] || continue
      pid=${cmd#/proc/}
      pid=${pid%/cmdline}
      raw=$(tr "\0" " " < "$cmd" 2>/dev/null || true)
      case "$raw" in
        "nginx: worker process"*) printf "%s\n" "$pid" ;;
      esac
    done
  '
}

nginx_worker_alive() {
  docker exec idiario-nginx-prod sh -c '
    cmd="/proc/$1/cmdline"
    [ -r "$cmd" ] || exit 1
    raw=$(tr "\0" " " < "$cmd" 2>/dev/null || true)
    case "$raw" in
      "nginx: worker process"*) exit 0 ;;
      *) exit 1 ;;
    esac
  ' sh "$1" 2>/dev/null
}

# proxy_read_timeout do nginx.conf é 300s. Passou disso, o próprio Nginx
# já encerrou o proxy; esperar mais não devolve a resposta ao cliente.
wait_old_nginx_workers() {
  local timeout="$1"
  shift
  local elapsed=0
  local alive pid

  if [ "$#" -eq 0 ]; then
    echo "  AVISO: workers antigos do Nginx não identificados."
    echo "  O Puma antigo vai concluir só o que ainda der no SIGTERM."
    return 0
  fi

  echo "  Aguardando pedidos já aceitos no slot antigo terminarem (até ${timeout}s)..."
  while [ "$elapsed" -lt "$timeout" ]; do
    alive=0
    for pid in "$@"; do
      [ -n "$pid" ] || continue
      if nginx_worker_alive "$pid"; then
        alive=1
        break
      fi
    done
    if [ "$alive" -eq 0 ]; then
      echo "  Pedidos já aceitos no slot antigo foram respondidos."
      return 0
    fi
    if [ "$elapsed" -gt 0 ] && [ $((elapsed % 15)) -eq 0 ]; then
      echo "  Ainda há pedido no slot antigo (${elapsed}s)..."
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "  AVISO: um pedido no slot antigo passou de ${timeout}s. Seguindo com o stop."
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
echo "==> 4/5 Chaveando Nginx para $NEW_SLOT (reload, sem derrubar a porta)..."
write_backend "$ACTIVE_SLOT" "$NEW_SLOT"

OLD_NGINX_WORKER_PIDS=""
INSIDE="$(nginx_upstream_inside)"
if [ "$INSIDE" != "$NEW_SLOT" ]; then
  echo "  AVISO: o container ainda vê '${INSIDE:-vazio}' (bind preso no inode antigo)."
  echo "  Reiniciando o Nginx uma vez para remontar o arquivo. Os próximos deploys só fazem reload."
  docker restart idiario-nginx-prod
  INSIDE="$(nginx_upstream_inside)"
  if [ "$INSIDE" != "$NEW_SLOT" ]; then
    echo "  ERRO: Nginx não carregou o novo config (esperado=$NEW_SLOT, atual=$INSIDE). Revertendo..."
    write_backend "$NEW_SLOT" "$ACTIVE_SLOT"
    docker restart idiario-nginx-prod
    exit 1
  fi
else
  OLD_NGINX_WORKER_PIDS="$(nginx_worker_pids | tr '\n' ' ' || true)"
  if ! reload_nginx; then
    echo "  ERRO: reload do Nginx falhou. Revertendo..."
    write_backend "$NEW_SLOT" "$ACTIVE_SLOT"
    reload_nginx || docker restart idiario-nginx-prod
    exit 1
  fi
fi
echo "  Nginx chaveado para $NEW_SLOT."

echo ""
echo "==> 5/5 Encerrando pedidos do slot antigo ($ACTIVE_SLOT) e atualizando Sidekiq..."

wait_old_nginx_workers 310 $OLD_NGINX_WORKER_PIDS
docker stop --time 300 "$OLD_CONTAINER" && docker rm "$OLD_CONTAINER" 2>/dev/null || true

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
