#!/bin/bash
set -euo pipefail

# ----- Read env variables (using your actual .env names) -----
MYSQL_HOST="${MYSQL_HOST:?}"
MYSQL_PORT="${MYSQL_PORT:?}"
MYSQL_DATABASE="${MYSQL_DATABASE:?}"
MYSQL_USER="${MYSQL_USER:?}"
MYSQL_PASSWORD_FILE="${MYSQL_PASSWORD_FILE:?}"

WP_TITLE="${WP_TITLE:?}"
WP_URL="${WP_URL:?}"

WP_ADMIN_USER="${WP_ADMIN_USER:?}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:?}"
WP_ADMIN_PASSWORD_FILE="${WP_ADMIN_PASSWORD_FILE:?}"

WP_USER="${WP_USER:?}"
WP_USER_EMAIL="${WP_USER_EMAIL:?}"
WP_USER_PASSWORD_FILE="${WP_USER_PASSWORD_FILE:?}"

PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"

# ----- Read passwords from files -----
DB_PASS=$(cat "${MYSQL_PASSWORD_FILE}")
WP_ADMIN_PASS=$(cat "${WP_ADMIN_PASSWORD_FILE}")
WP_USER_PASS=$(cat "${WP_USER_PASSWORD_FILE}")

# ----- Construct DB host -----
DB_HOST="${MYSQL_HOST}:${MYSQL_PORT}"

echo "Starting WordPress setup with DB: ${DB_HOST}"

# ----- Download WordPress if not present -----
if [ ! -f "wp-includes/version.php" ]; then
  echo "[wordpress] Downloading WordPress..."
  curl -fsSL https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1
  chown -R www-data:www-data /var/www/html
  chmod -R 755 /var/www/html
fi

# ----- Create wp-config.php if not exists -----
if [ ! -f "wp-config.php" ]; then
  echo "[wordpress] Creating wp-config.php..."
  cp wp-config-sample.php wp-config.php
  
  # Set database configuration
  sed -i "s/database_name_here/${MYSQL_DATABASE}/g" wp-config.php
  sed -i "s/username_here/${MYSQL_USER}/g" wp-config.php
  sed -i "s/password_here/${DB_PASS}/g" wp-config.php
  sed -i "s/localhost/${DB_HOST}/g" wp-config.php
  
  # Add security salts
  echo "[wordpress] Adding security salts..."
  curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php
  
  # Force HTTPS
  echo "define('WP_DEBUG', false);" >> wp-config.php
  echo "define('FS_METHOD', 'direct');" >> wp-config.php
fi

# ----- Wait for database -----
echo "[wordpress] Waiting for database (up to 30s)..."
for i in {1..10}; do
  if mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[wordpress] Database connected!"
    break
  fi
  echo "[wordpress] Waiting for database... (attempt $i/10)"
  sleep 3
done

# ----- Install WordPress -----
echo "[wordpress] Installing WordPress..."
php -r "
define('WP_INSTALLING', true);
require_once 'wp-load.php';
require_once ABSPATH . 'wp-admin/includes/upgrade.php';

// Install WordPress
wp_install(
    getenv('WP_TITLE'),
    getenv('WP_ADMIN_USER'),
    getenv('WP_ADMIN_EMAIL'),
    true,
    '',
    getenv('WP_ADMIN_PASS')
);

// Update site URLs
update_option('siteurl', getenv('WP_URL'));
update_option('home', getenv('WP_URL'));
" WP_TITLE="${WP_TITLE}" WP_ADMIN_USER="${WP_ADMIN_USER}" WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL}" WP_ADMIN_PASS="${WP_ADMIN_PASS}" WP_URL="${WP_URL}"

echo "[wordpress] Setup complete! Starting PHP-FPM..."
exec php-fpm82 -F