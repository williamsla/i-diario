#!/bin/bash

set -euo pipefail

# Define a raiz do projeto
ROOT_DIR="$(dirname "$0")/.."
cd "$ROOT_DIR"

# Configuração do log
LOG_FILE="$ROOT_DIR/log/auto_update.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec >> "$LOG_FILE" 2>&1

echo "===== INÍCIO DO AUTO UPDATE $(date) ====="

# -----------------------------
# Detecta e carrega gerenciador Ruby
# -----------------------------
if [ -f "/root/.asdf/asdf.sh" ]; then
    echo "Carregando ASDF..."
    . /root/.asdf/asdf.sh || exit 1
    export PATH="/root/.asdf/shims:/root/.asdf/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
elif command -v rbenv >/dev/null 2>&1; then
    echo "Carregando Rbenv..."
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init -)"
elif [ -s "$HOME/.rvm/scripts/rvm" ]; then
    echo "[INFO] Carregando RVM..."
    source "$HOME/.rvm/scripts/rvm"
elif command -v chruby >/dev/null 2>&1; then
    echo "[INFO] Carregando chruby..."
    source /usr/local/share/chruby/chruby.sh
    source /usr/local/share/chruby/auto.sh
else
    echo "[INFO] Nenhum gerenciador Ruby detectado, usando Ruby global"
fi

echo "[INFO] Ruby ativo: $(ruby -v)"
echo "[INFO] Caminho do Ruby: $(which ruby)"


# Executa backup antes de atualizar. Roda como um subshell para isolar alterações de diretorios feitas pelo backup no auto_update.
( ./script/backup.sh )


echo "===> Iniciando sincronizações ..."
bundle exec rails send_notification:absences RAILS_ENV=production
bundle exec rake refresh_pedagogical_tracking_views RAILS_ENV=production
bundle exec rake ieducar_api:synchronize RAILS_ENV=production


echo "===> FAZENDO COPIA DE CONFIGURAÇÕES"
cp ./config/secrets.yml ../
cp ./config/database.yml ../

git fetch --all
# Salva a saída do git pull
GIT_OUTPUT=$(git pull)

# Verifica se houve alterações
if echo "$GIT_OUTPUT" | grep -q "Already up to date\|Atualizado"; then
  echo "Nenhuma alteração detectada. Encerrando script."
  exit 0
fi

echo "$GIT_OUTPUT"

#echo "===> INSTALANDO AS GEMS"
# ERROS COMUNS
#The --deployment flag requires a Gemfile.lock 
## Ver: https://stackoverflow.com/questions/14796095/the-deployment-flag-requires-a-gemfile-lock
## Remove BUNDLE_FROZEN: "true" from .bundle/config file and run bundle again.
## nano .bundle/config
# SE O ERRO PERSISTIR -> bundle config --delete deployment
#gem update --system 3.2.3

###################

## se der erro "deployment/frozen"
# bundle config --delete deployment
# bundle config --delete frozen

echo "===> VERIFICANDO GEMS"
if ! bundle check --path=vendor/bundle > /dev/null 2>&1; then
  echo "===> Gems faltando ou Gemfile.lock mudou, instalando"

  rm -rf vendor/bundle
  RAILS_ENV=production bundle install --deployment --without development test
else
  echo "===> Gems já estão atualizadas, pulando"
fi

echo "===> VERIFICANDO PACOTES YARN"
if ! yarn check --integrity > /dev/null 2>&1; then
  echo "===> Instalando pacotes Yarn..."
  yarn cache clean && yarn install --check-files
else
  echo "===> Pacotes Yarn já instalados."
fi

echo "===> RODANDO MIGRATIONS"    
RAILS_ENV=production bundle exec rake db:migrate

echo "===> COMPILANDO CSS"
RAILS_ENV=production bundle exec rake assets:precompile

echo "===> REINICIANDO O SERVIÇO rails E sidekiq"
systemctl restart rails-server
systemctl restart sidekiq-main
systemctl restart sidekiq-sync
systemctl restart sidekiq-exams

echo "===> PARANDO SERVIÇO de envio automático de avaliações"
if [ -f tmp/auto_post.pid ]; then
  PID=$(cat tmp/auto_post.pid)
  if ps -p $PID > /dev/null 2>&1; then
    echo "Parando processo anterior (PID $PID)..."
    kill -9 $PID
  fi
  rm -f tmp/auto_post.pid
fi

echo "===> INICIANDO SERVIÇO de envio automático de avaliações"
nohup bundle exec rake post_avaliations RAILS_ENV=production > log/auto_post.log 2>&1 &
echo $! > tmp/auto_post.pid


# add to crontab to run this script daily
# sudo crontab -e
# 00 04 * * * /var/www/idiario/auto_update.sh >> /var/www/idiario/log/auto_update.log 2>&1
