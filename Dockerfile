FROM ruby:2.4.10-slim-buster

RUN set -eux \
  && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99archive \
  && sed -i \
    -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
    -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
    /etc/apt/sources.list

RUN apt-get update -qq
RUN apt-get install -y \
    build-essential \
    libpq-dev nodejs \
    npm \
    git \
    shared-mime-info \
    net-tools \
    software-properties-common \
    bash-completion \
    libpam-pwquality \
    acl \
    policycoreutils \	
    libxslt-dev \
    libxml2-dev \
    zlib1g-dev \
    build-essential

RUN npm i -g yarn

ENV app /app

RUN mkdir $app

WORKDIR $app

RUN gem install bundler:1.17.3

# COPY Gemfile Gemfile.lock /app/

ENV BUNDLE_PATH /box
