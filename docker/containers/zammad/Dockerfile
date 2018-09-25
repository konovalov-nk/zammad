FROM ruby:2.4.4-slim
MAINTAINER Zammad <info@zammad.org>
ARG BUILD_DATE
ARG BUNDLE_WITHOUT
ARG ZAMMAD_USER

ENV ZAMMAD_DIR /opt/zammad
ENV RAILS_SERVER puma
ENV GOSU_VERSION 1.10
ENV ZAMMAD_READY_PATH ${ZAMMAD_DIR}/tmp
ENV ZAMMAD_READY_FILE ${ZAMMAD_DIR}/tmp/zammad.ready

# install dependencies & gosu
RUN BUILD_DEPENDENCIES="build-essential ca-certificates curl dirmngr git gnupg2 libffi-dev libpq5 libpq-dev libsqlite3-dev nginx rsync" \
    set -ex \
	  && apt-get update && apt-get install -y --no-install-recommends ${BUILD_DEPENDENCIES} && rm -rf /var/lib/apt/lists/* \
	  && curl -s -J -L -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$(dpkg --print-architecture)" \
	  && curl -s -J -L -o /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$(dpkg --print-architecture).asc" \
	  && export GNUPGHOME="$(mktemp -d)" \
	  && for server in $(shuf -e ha.pool.sks-keyservers.net \
	                             hkp://p80.pool.sks-keyservers.net:80 \
	                             keyserver.ubuntu.com \
                                 hkp://keyserver.ubuntu.com:80 \
                                 pgp.mit.edu) ; do \
         gpg --keyserver "$server" --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 && break || : ; done \
	  && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	  && rm -rf "${GNUPGHOME}" /usr/local/bin/gosu.asc \
	  && chmod +x /usr/local/bin/gosu \
	  && gosu nobody true

# install zammad
RUN groupadd -g 1000 ${ZAMMAD_USER} \
    && useradd -M -d ${ZAMMAD_DIR} -s /bin/bash -u 1000 -g 1000 ${ZAMMAD_USER}

WORKDIR ${ZAMMAD_DIR}

# all build stages are cached
COPY Gemfile Gemfile.lock ${ZAMMAD_DIR}/
RUN bundle install --jobs $(nproc) --without ${BUNDLE_WITHOUT}

# use current branch as a source
ADD . ${ZAMMAD_DIR}
RUN contrib/packager.io/fetch_locales.rb
RUN cp config/database/database.yml config/database.yml \
    && chown -R ${ZAMMAD_USER}:${ZAMMAD_USER} ${ZAMMAD_DIR}

# init scripts
COPY docker/containers/zammad/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
