#!/bin/bash

TZ="America/Sao_Paulo"
export TZ

set -euo pipefail

is_dawn() {
  hour=$(date +%H)
  if [ "$hour" -lt 6 ]; then
    return 0   # true in bash
  else
    return 1   # false in bash
  fi
}

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
elif [ -s "/etc/profile.d/rvm.sh" ]; then
    echo "[INFO] Carregando RVM global (/etc/profile.d/rvm.sh)..."
    source "/etc/profile.d/rvm.sh"
elif [ -s "/usr/local/rvm/scripts/rvm" ]; then
    echo "[INFO] Carregando RVM global (/usr/local/rvm/scripts/rvm)..."
    source "/usr/local/rvm/scripts/rvm"
elif [ -s "$HOME/.rvm/scripts/rvm" ]; then
    echo "[INFO] Carregando RVM do usuário ($HOME/.rvm/scripts/rvm)..."
    source "$HOME/.rvm/scripts/rvm"
else
    echo "[INFO] Nenhum gerenciador Ruby detectado, usando Ruby global"
    export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
fi

echo "[INFO] Ruby ativo: $(ruby -v)"
echo "[INFO] Caminho do Ruby: $(which ruby)"


# Executa backup antes de atualizar. Roda como um subshell para isolar alterações de diretorios feitas pelo backup no auto_update.
if is_dawn; then
  ( ./script/backup.sh )
fi

echo "===> Iniciando sincronizações ..."
bundle exec rake aulas:atualizar ANO=2025 RAILS_ENV=production 
bundle exec rake send_notification:absences RAILS_ENV=production
bundle exec rake refresh_pedagogical_tracking_views RAILS_ENV=production

# Verifica se é madrugada ou dia para definir o tipo de sincronização
if is_dawn; then
  # Madrugada → full
  
  if [[ "${CIDADE_COD:-}" == *delmiro* ]]; then
    echo "Sincronizando Delmiro..."
    
    sudo systemctl stop rails-server.service
    RAILS_ENV=production bundle exec rake ieducar_api:synchronize[true,true]
  
    sleep 30m
    sudo systemctl restart rails-server.service
  
  else
    RAILS_ENV=production bundle exec rake ieducar_api:synchronize[true,true]
  fi
else
  # Durante o dia → simples
  RAILS_ENV=production bundle exec rake ieducar_api:synchronize[false,true]
fi


echo "===> FAZENDO COPIA DE CONFIGURAÇÕES"
cp ./config/secrets.yml ../
cp ./config/database.yml ../

git fetch --all
# Salva a saída do git pull
GIT_OUTPUT=$(git pull)

# Verifica se houve alterações
if echo "$GIT_OUTPUT" | grep -q "Already up to date\|Atualizado"; then
  echo "Nenhuma alteração detectada. Preparando para encerrar script."

  echo "Verificando envio de avaliações..."
  PIDS=$(pgrep -f post_avaliations || true)
  if [ -n "$PIDS" ]; then 
    echo "===> O envio automático de avaliações já está rodando (PIDs: $PIDS)"
  else
    echo "===> INICIANDO o envio automático de avaliações"
    nohup bundle exec rake post_avaliations:init ORDER=asc RAILS_ENV=production > log/auto_post.log 2>&1 &
    echo $! > tmp/auto_post.pid

    nohup bundle exec rake post_avaliations:init ORDER=desc RAILS_ENV=production > log/auto_post_desc.log 2>&1 &
    echo $! > tmp/auto_post_desc.pid
  fi 

  exit 0 #encerra script
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
if [ -f ../scripts/restart-idiario.sh ]; then
  ../scripts/restart-idiario.sh
else
  ./script/restart.sh
fi


echo "===> PARANDO SERVIÇO de envio automático de avaliações"
if [ -f tmp/auto_post.pid ]; then
  PID=$(cat tmp/auto_post.pid)
  if ps -p $PID > /dev/null 2>&1; then
    echo "Parando processo anterior (PID $PID)..."
    kill -9 $PID
  fi
  rm -f tmp/auto_post.pid
fi

# Para processos que contenham 'post_avaliations' no comando
echo "Verificando processos com 'post_avaliations'..."
PIDS=$(pgrep -f post_avaliations || true)
if [ -n "$PIDS" ]; then
  echo "Matando processos: $PIDS"
  kill -9 $PIDS
else
  echo "Nenhum processo 'post_avaliations' encontrado."
fi

echo "===> INICIANDO SERVIÇO de envio automático de avaliações"
nohup bundle exec rake post_avaliations:init ORDER=asc RAILS_ENV=production > log/auto_post.log 2>&1 &
echo $! > tmp/auto_post.pid

nohup bundle exec rake post_avaliations:init ORDER=desc RAILS_ENV=production > log/auto_post_desc.log 2>&1 &
echo $! > tmp/auto_post_desc.pid


# add to crontab to run this script daily
# sudo crontab -e
# 00 04 * * * /var/www/idiario/auto_update.sh
