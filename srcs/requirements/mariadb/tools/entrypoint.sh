#!/bin/bash
set -euo pipefail

# Env from .env (compose) and secrets
DB_NAME="${MYSQL_DATABASE:?}"
DB_USER="${MYSQL_USER:?}"
DB_PASS_FILE="${MYSQL_PASSWORD_FILE:?}"
ROOT_PASS_FILE="${MYSQL_ROOT_PASSWORD_FILE:?}"

DB_PASS="$(cat "${DB_PASS_FILE}")"
ROOT_PASS="$(cat "${ROOT_PASS_FILE}")"

# Initialize database if empty
if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "[mariadb] Initializing data directory..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql --auth-root-authentication-method=normal >/dev/null

  echo "[mariadb] Bootstrapping..."
  mariadbd --user=mysql --datadir=/var/lib/mysql --skip-networking --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid --bootstrap <<SQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
fi

echo "[mariadb] Starting server..."
exec mariadbd --user=mysql --datadir=/var/lib/mysql --console
