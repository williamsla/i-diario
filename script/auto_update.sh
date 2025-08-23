#!/bin/bash

# carrega o ambiente do asdf
. /root/.asdf/asdf.sh

cd /var/www/idiario

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

# add to crontab to run this script daily
# sudo crontab -e
# 00 04 * * * /var/www/idiario/auto_update.sh >> /var/www/idiario/log/auto_update.log 2>&1
