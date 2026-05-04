#!/bin/sh
set -e

# Migrate só ao subir o Puma (serviço web). Assim `docker compose run ... rake db:create`
# ou entity:setup não tentam migrar antes do banco existir.
migrate_before_web=false
if [ "${RUN_DB_MIGRATE_ON_START:-1}" != "0" ]; then
  joined=$(printf '%s ' "$@")
  case "$joined" in
    *puma*|*Puma*) migrate_before_web=true ;;
  esac
fi

if [ "$migrate_before_web" = true ]; then
  echo "==> db:migrate antes do Puma (RUN_DB_MIGRATE_ON_START=${RUN_DB_MIGRATE_ON_START:-1})"
  bundle exec rake db:migrate
fi

exec "$@"
