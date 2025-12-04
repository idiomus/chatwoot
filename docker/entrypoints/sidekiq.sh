#!/bin/sh

if [ -f /app/docker/entrypoints/helpers/load_secrets.sh ]; then
  set +x
  echo "Loading secrets from _FILE variables..."
  . /app/docker/entrypoints/helpers/load_secrets.sh
fi

set -x

echo "Waiting for postgres to become ready...."

$(docker/entrypoints/helpers/pg_database_url.rb)
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

until $PG_READY
do
  sleep 2;
done

echo "Database ready to accept connections."

exec "$@"
