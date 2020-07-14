[![Latest Release](https://img.shields.io/github/release/portabilis/i-diario.svg?label=latest%20release)](https://github.com/portabilis/i-diario/releases)
[![Maintainability](https://api.codeclimate.com/v1/badges/92cee0c65548b4b4653b/maintainability)](https://codeclimate.com/github/portabilis/i-diario/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/92cee0c65548b4b4653b/test_coverage)](https://codeclimate.com/github/portabilis/i-diario/test_coverage)

# i-Diário

Portal do professor integrado com o software livre [i-Educar](https://github.com/portabilis/i-educar).

## Comunicação

Acreditamos que o sucesso do projeto depende diretamente da interação clara e
objetiva entre os membros da Comunidade. Por isso, estamos definindo algumas
políticas para que estas interações nos ajudem a crescer juntos! Você pode
consultar algumas destas boas práticas em nosso [código de
conduta](https://github.com/portabilis/i-diario/blob/master/CODE_OF_CONDUCT.md).

Além disso, gostamos de meios de comunicação assíncrona, onde não há necessidade de
respostas em tempo real. Isso facilita a produtividade individual dos
colaboradores do projeto.

| Canal de comunicação | Objetivos |
|----------------------|-----------|
| [Fórum](https://forum.ieducar.org) | - Tirar dúvidas <br>- Discussões de como instalar a plataforma<br> - Discussões de como usar funcionalidades<br> - Suporte entre membros de comunidade<br> - FAQ da comunidade (sobre o produto e funcionalidades) |
| [Issues do Github](https://github.com/portabilis/i-diario/issues/new/choose) | - Sugestão de novas funcionalidades<br> - Reportar bugs<br> - Discussões técnicas |
| [Telegram](https://t.me/ieducar ) | - Comunicar novidades sobre o projeto<br> - Movimentar a comunidade<br>  - Falar tópicos que **não** demandem discussões profundas |

Qualquer outro grupo de discussão não é reconhecido oficialmente pela
comunidade i-Educar e não terá suporte da Portabilis - mantenedora do projeto.

## Instalação

Há duas formas de fazer a instalação:

- [Instalação utilizando Docker](#Instalação-utilizando-Docker)
- [Instalação em Servidor](#Instalação-em-Servidor-(Testado-no-Ubuntu-18.04))

Para instalar o projeto execute todos.

### Instalação utilizando Docker

> ATENÇÃO: Essa forma de instação tem o objetivo de facilitar demonstrações e desenvolvimento. Não é recomendado para
> ambientes de produção!

Para instalar o projeto execute todos os passos abaixo.

Clone o repositório:

```bash
git clone https://github.com/portabilis/i-diario.git && cd i-diario
```

Faça o build das imagens Docker utilizadas no projeto (pode levar alguns minutos) e inicie os containers da aplicação:

```bash
docker-compose up -d --build
```

Use o comando `docker-compose logs -f app` para acompanhar o log da aplicação.

Aguarde a instalação finalizar até algo similar aparecer na tela:

```log
idiario     | => Ctrl-C to shutdown server
idiario     | Puma starting in single mode...
idiario     | * Version 4.3.1 (ruby 2.3.7-p456), codename: Mysterious Traveller
idiario     | * Min threads: 0, max threads: 16
idiario     | * Environment: development
idiario     | * Listening on tcp://0.0.0.0:3000
idiario     | Use Ctrl-C to stop
```

Veja como fazer o seu [primeiro acesso](#Primeiro-acesso).

#### Personalizando a instalação via Docker

Você pode criar um arquivo `docker-compose.override.yml` para personalizar sua instalação do i-Diário, mudando as portas
dos serviços ou o mapeamento dos volumes extras para a aplicação.

### Instalação em Servidor (Testado no Ubuntu 18.04)

- Instale o Ruby 2.3.7 (recomendamos uso de um gerenciador de versões como [Rbenv](https://github.com/rbenv/rbenv) ou [Rvm](https://rvm.io/))
- Instale o Postgres e faça a configuração em `database.yml`
- Instale a biblioteca `libpq-dev`

```bash
sudo apt install libpq-dev
```

- Instale a gem Bundler:

```bash
gem install bundler -v '1.17.3'
```

- Instale as gems:

```bash
bundle install
```

- Crie e configure o arquivo `config/secrets.yml` conforme o exemplo:

```yaml
development:
  secret_key_base: CHAVE_SECRETA
  SMTP_ADDRESS: SMTP_ADDRESS
  SMTP_PORT: SMTP_PORT
  SMTP_DOMAIN: SMTP_DOMAIN
  SMTP_USER_NAME: SMTP_USER_NAME
  SMTP_PASSWORD: SMTP_PASSWORD
  BUCKET_NAME: S3_BUCKET_NAME
```

_Nota: Você pode gerar uma chave secreta usando o comando `bundle exec rake secret`_

- Crie e configure o arquivo `config/aws.yml` conforme o exemplo:

```yaml
development:
  access_key_id: AWS_ACCESS_KEY_ID
  secret_access_key: AWS_SECRET_ACCESS_KEY

```

- Crie o banco de dados:

```bash
bundle exec rake db:create
bundle exec rake db:migrate
```

- Crie as páginas de erro para desenvolvimento:

```bash
cp public/404.html.sample public/404.html
cp public/500.html.sample public/500.html
```

- Crie uma entidade:

```bash
bundle exec rake entity:setup NAME=prefeitura DOMAIN=localhost DATABASE=prefeitura_diario
```

Inicie o servidor:

```bash
bundle exec rails server
```

### Primeiro acesso

Antes de realizar o primeiro acesso, crie um usuário administrador:

```bash
# (Docker) docker-compose exec app bundle exec rails console
bundle exec rails console
```

Crie o usuário administrador, substitua as informações que deseje:

```ruby
Entity.last.using_connection {
  User.create!(
    email: 'admin@domain.com.br',
    password: '123456789',
    password_confirmation: '123456789',
    status: 'active',
    kind: 'employee',
    admin:  true
  )
}
```

Agora você poderá acessar o i-Diário na URL [http://localhost:3000](http://localhost:3000) com as credenciais fornecidas
no passo anterior.

## Sincronização com i-Educar

- Para fazer a sincronização entre i-Educar e i-Diário é necessário estar com o Sidekiq rodando:

```bash
# (Docker) docker-compose exec app bundle exec sidekiq -d
bundle exec sidekiq -d
```

- Acessar Configurações > Api de Integraçao e configurar os dados do sincronismo
- Acessar Configurações > Unidades e clicar em **Sincronizar**
- Acessar Calendário letivo, clicar em **Sincronizar** e configurar os calendários
- Acessar Configurações > Api de Integração
  - Existem dois botões nessa tela:
    - Sincronizar: Ao clicar nesse botão, será verificado a ultima data de sincronização e somente vai sincronizar os dados inseridos/atualizados/deletados após essa data.
    - Sincronização completa: Esse botão apenas aparece para o usuário administrador e ao clicar nesse botão, não vai fazer a verificação de data, sincronizando todos os dados de todos os anos.

_Nota: Após esses primeiros passos, recomendamos que a sincronização rode pelo menos diariamente para manter o i-Diário atualizado com o i-Educar_

## Executar os testes

```bash
# (Docker) docker-compose exec app RAILS_ENV=test bundle exec rake db:create
RAILS_ENV=test bundle exec rake db:create

# (Docker) docker-compose exec app RAILS_ENV=test bundle exec rake db:migrate
RAILS_ENV=test bundle exec rake db:migrate
```

```bash
# (Docker) docker-compose exec app bin/rspec spec
bin/rspec spec
```

## Upgrades

### Upgrade para a versão 1.1.0

Nessa atualização a sincronização entre i-Educar e i-Diário foi completamente reestruturada e com isso o i-Diário passa
a ter dependência da versão **2.1.18** do i-Educar.

Para o upgrade é necessário atualizar o i-Diário para a versão [1.1.0](https://github.com/portabilis/i-diario/releases/tag/1.1.0).

Parar o sidekiq:

```bash
ps -ef | grep sidekiq | grep -v grep | awk '{print $2}' | xargs kill -TERM && sleep 20
```

* Executar as migrations:

```bash
# (Docker) docker-compose exec app bundle exec rake db:migrate
bundle exec rake db:migrate
```

* Iniciar o sidekiq:

```bash
# (Docker) docker-compose exec app bundle exec sidekiq -d --logfile log/sidekiq.log
bundle exec sidekiq -d --logfile log/sidekiq.log
```

* Executar a rake task que irá fazer a atualização do banco de dados e executar a sincronização completa em todas as
entidades:

```bash
# (Docker) docker-compose exec app bundle exec rake upgrade:versions:1_1_0
bundle exec rake upgrade:versions:1_1_0
```
