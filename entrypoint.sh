#!/bin/sh

echo "Waiting for postgres..."

while ! nc -z db 5432; do
    sleep 0.1
done

echo "PostgreSQL started"

python $APP_HOME/manage.py migrate
python $APP_HOME/manage.py create_user

exec "$@"