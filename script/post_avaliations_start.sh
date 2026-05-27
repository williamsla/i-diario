#!/bin/bash
# Dispara post_avaliations:init por DOMAIN no container Docker (execução única por vez).
#
# Pré-requisito: stack em execução
#   docker compose -f docker-compose.production.yml --env-file .env.production up -d
#
# Cron (a cada hora):
#   0 * * * * TZ=America/Sao_Paulo /var/www/idiario/script/post_avaliations_start.sh >> /var/www/idiario/log/post_avaliations_cron.log 2>&1
#
# Domínios: config/post_avaliations_domains

set -euo pipefail

export TZ="${TZ:-America/Sao_Paulo}"

ROOT_DIR="${IDIARIO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT_DIR"

COMPOSE="${COMPOSE:-docker compose -f docker-compose.production.yml --env-file .env.production}"
# Produção usa app-blue / app-green (docker-compose.production.yml), não "app".
COMPOSE_SERVICE="${COMPOSE_SERVICE:-app-blue}"
CONTAINER_NAME="${CONTAINER_NAME:-idiario-app-blue}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/log/post_avaliations}"
LOCK_DIR="${LOCK_DIR:-$ROOT_DIR/tmp/post_avaliations_locks}"

mkdir -p "$LOG_DIR" "$LOCK_DIR"

DOMAINS_FILE="${DOMAINS_FILE:-$ROOT_DIR/config/post_avaliations_domains}"

if [[ ! -f "$DOMAINS_FILE" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERRO] Arquivo não encontrado: ${DOMAINS_FILE}"
  if [[ -f "${DOMAINS_FILE}.example" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERRO] Copie o exemplo: cp ${DOMAINS_FILE}.example ${DOMAINS_FILE}"
  fi
  exit 1
fi

mapfile -t DOMAINS < <(grep -vE '^\s*($|#)' "$DOMAINS_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERRO] Nenhum domínio em ${DOMAINS_FILE}."
  exit 1
fi

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

safe_name() {
  echo "$1" | tr '.' '_' | tr -cd '[:alnum:]_-'
}

ensure_docker_running() {
  if ! command -v docker >/dev/null 2>&1; then
    log "[ERRO] Docker não instalado ou não está no PATH."
    exit 1
  fi

  if [[ ! -f "$ROOT_DIR/docker-compose.production.yml" ]]; then
    log "[ERRO] docker-compose.production.yml não encontrado em ${ROOT_DIR}"
    exit 1
  fi

  if [[ ! -f "$ROOT_DIR/.env.production" ]]; then
    log "[ERRO] .env.production não encontrado em ${ROOT_DIR}"
    exit 1
  fi

  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    log "[ERRO] Container ${CONTAINER_NAME} não está em execução."
    log "[ERRO] Suba o stack: docker compose -f docker-compose.production.yml --env-file .env.production up -d"
    exit 1
  fi
}

domain_is_running() {
  local domain="$1"
  $COMPOSE exec -T "$COMPOSE_SERVICE" bash -c '
    set -euo pipefail
    domain="$1"
    for pid in $(pgrep -f "post_avaliations:init" 2>/dev/null || true); do
      [[ -r "/proc/${pid}/environ" ]] || continue
      if tr "\0" "\n" < "/proc/${pid}/environ" | grep -qx "DOMAIN=${domain}"; then
        exit 0
      fi
    done
    exit 1
  ' -- "$domain"
}

start_domain() {
  local domain="$1"
  local safe log_file lock_file

  safe="$(safe_name "$domain")"
  log_file="${LOG_DIR}/${safe}.log"
  lock_file="${LOCK_DIR}/${safe}.lock"

  exec 9>"$lock_file"
  if ! flock -n 9; then
    log "[SKIP] ${domain} — script já rodando para este domínio (flock)."
    return 0
  fi

  if domain_is_running "$domain"; then
    log "[SKIP] ${domain} — post_avaliations:init já em execução no container."
    return 0
  fi

  log "[START] ${domain} → ${log_file}"

  nohup $COMPOSE exec -T "$COMPOSE_SERVICE" \
    env RAILS_ENV=production DOMAIN="$domain" ORDER="${ORDER:-asc}" \
    bundle exec rake post_avaliations:init \
    >>"$log_file" 2>&1 &

  disown || true
}

ensure_docker_running

log "===== post_avaliations_start (${#DOMAINS[@]} domínio(s), docker/${COMPOSE_SERVICE}, ${DOMAINS_FILE}) ====="

for domain in "${DOMAINS[@]}"; do
  [[ -n "$domain" ]] || continue
  start_domain "$domain"
done

log "===== fim ====="
