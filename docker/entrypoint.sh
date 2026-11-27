#!/bin/sh
# Punto de entrada del contenedor EPM.
# 1) (opcional) crea el esquema si la base esta vacia  2) arranca Gunicorn.
set -e

if [ "${DB_AUTO_INIT:-true}" = "true" ]; then
  python /app/docker/init_db.py
fi

exec "$@"
