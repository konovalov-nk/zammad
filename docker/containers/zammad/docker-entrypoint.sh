#!/bin/bash

set -e

: "${POSTGRESQL_DB:=zammad_development}"
: "${POSTGRESQL_DB_CREATE:=true}"
: "${RAILSSERVER_HOST:=zammad-railsserver}"
: "${RAILSSERVER_PORT:=3000}"
: "${ZAMMAD_WEBSOCKET_HOST:=zammad-websocket}"
: "${ZAMMAD_WEBSOCKET_PORT:=6042}"
: "${NGINX_SERVER_NAME:=_}"


if [ "$1" = 'zammad-bash' ]; then
  echo "zammad-bash..."
  /bin/bash
fi

if [ "$1" = 'zammad-init' ]; then
  echo "initialising / updating database..."

  # db migrate
  set +e
  bundle exec rake db:migrate &> /dev/null
  DB_CHECK="$?"
  set -e

  if [ "${DB_CHECK}" != "0" ]; then
    if [ "${POSTGRESQL_DB_CREATE}" == "true" ]; then
      bundle exec rake db:create
    fi
    bundle exec rake db:migrate
    bundle exec rake db:seed
  fi

  # es config
  bundle exec rails r "Setting.set('es_url', '${ES_URL}')"

  if [ -n "${ELASTICSEARCH_USER}" ] && [ -n "${ELASTICSEARCH_PASS}" ]; then
    bundle exec rails r "Setting.set('es_user', \"${ELASTICSEARCH_USER}\")"
    bundle exec rails r "Setting.set('es_password', \"${ELASTICSEARCH_PASS}\")"
  fi

  if [ -z "$(curl -s ${ES_URL}/_cat/indices |grep zammad)" ]; then
    curl -s ${ES_URL}/_cat/indices
    echo "rebuilding es searchindex..."
    bundle exec rake searchindex:rebuild
  fi

  mkdir -p ${ZAMMAD_READY_PATH}
  chown -R ${ZAMMAD_USER}:${ZAMMAD_USER} ${ZAMMAD_DIR}
  su -c "echo 'zammad-init' > ${ZAMMAD_READY_FILE}" ${ZAMMAD_USER}

  # prevent container from exiting (for healthcheck)
  sleep infinity
fi


if [ "$1" = 'zammad-nginx' ]; then
  if [ -z "$(env|grep KUBERNETES)" ]; then
    echo "configuring nginx..."
    sed -e "s#server .*:3000#server ${RAILSSERVER_HOST}:${RAILSSERVER_PORT}#g" -e "s#server .*:6042#server ${ZAMMAD_WEBSOCKET_HOST}:${ZAMMAD_WEBSOCKET_PORT}#g" -e "s#server_name .*#server_name ${NGINX_SERVER_NAME};#g" -e 's#/var/log/nginx/zammad.\(access\|error\).log#/dev/stdout#g' < contrib/nginx/zammad_dev.conf > /etc/nginx/sites-enabled/default
  fi

  exec /usr/sbin/nginx -g 'daemon off;'
fi


if [ "$1" = 'zammad-railsserver' ]; then
  echo "starting railsserver..."
  exec gosu ${ZAMMAD_USER}:${ZAMMAD_USER} bundle exec rails server puma -b [::] -p ${RAILSSERVER_PORT} -e ${RAILS_ENV}
fi


if [ "$1" = 'zammad-scheduler' ]; then
  echo "starting scheduler..."
  exec gosu ${ZAMMAD_USER}:${ZAMMAD_USER} bundle exec script/scheduler.rb run
fi


if [ "$1" = 'zammad-websocket' ]; then
  echo "starting websocket server..."
  exec gosu ${ZAMMAD_USER}:${ZAMMAD_USER} bundle exec script/websocket-server.rb -b 0.0.0.0 -p ${ZAMMAD_WEBSOCKET_PORT} start
fi


if [ "$1" = 'zammad-testing' ]; then
  CONTAINER_ID=$(head -1 /proc/self/cgroup|cut -d/ -f3 | cut -c1-12)
  echo "starting testing..."

  export RAILS_ENV=test
  . script/bootstrap.sh

  echo "you can now run 'docker exec -it ${CONTAINER_ID} /bin/bash'..."
  echo "rspec tests: bundle exec rspec"
  echo "rails tests: bundle exec rake test:units"
  echo "rails tests: bundle exec rake test:controllers"

  # prevent container from exiting (for shell access)
  sleep infinity
fi

