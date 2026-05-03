#!/bin/sh
set -e

# RUN_DB_MIGRATE_ON_START=0 desativa (ex.: Sidekiq). App web usa 1 por padrão.
if [ "${RUN_DB_MIGRATE_ON_START:-1}" != "0" ]; then
  echo "==> db:migrate (RUN_DB_MIGRATE_ON_START=${RUN_DB_MIGRATE_ON_START:-1})"
  bundle exec rake db:migrate
fi

exec "$@"
