#!/bin/bash
# Dispara post_avaliations:init por DOMAIN (execução única; não inicia se já estiver rodando).
#
# Cron (a cada hora):
#   0 * * * * TZ=America/Sao_Paulo /opt/idiario/script/post_avaliations_start.sh >> /opt/idiario/log/post_avaliations_cron.log 2>&1
#  
# Domínios: config/post_avaliations_domains (copie de post_avaliations_domains.example).
# Sobrescreva com DOMAINS_FILE=/caminho/outro.txt se necessário.
# Listar do banco:
#   docker compose -f docker-compose.production.yml --env-file .env.production exec -T idiario-web-prod \
#     bundle exec rails runner "puts Entity.enable_to_sync.pluck(:domain)"

set -euo pipefail

export TZ="${TZ:-America/Sao_Paulo}"

ROOT_DIR="${IDIARIO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT_DIR"

COMPOSE="${COMPOSE:-docker compose -f docker-compose.production.yml --env-file .env.production}"
CONTAINER="${CONTAINER:-idiario-web-prod}"
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

# DOMAIN fica no ambiente do processo, não na linha de comando — checa /proc/PID/environ
domain_is_running() {
  local domain="$1"
  $COMPOSE exec -T "$CONTAINER" bash -c '
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
    log "[SKIP] ${domain} — post_avaliations:init já em execução."
    return 0
  fi

  log "[START] ${domain} → ${log_file}"

  # Processo no container; log no host (nohup mantém o exec após o cron sair).
  nohup $COMPOSE exec -T "$CONTAINER" \
    env RAILS_ENV=production DOMAIN="$domain" ORDER="${ORDER:-asc}" \
    bundle exec rake post_avaliations:init \
    >>"$log_file" 2>&1 &

  disown || true
}

log "===== post_avaliations_start (${#DOMAINS[@]} domínio(s), ${DOMAINS_FILE}) ====="

for domain in "${DOMAINS[@]}"; do
  [[ -n "$domain" ]] || continue
  start_domain "$domain"
done

log "===== fim ====="
