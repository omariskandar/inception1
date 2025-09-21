#!/usr/bin/env bash
set -euo pipefail

# Expect these from docker-compose:
# DB_HOST DB_NAME DB_USER DB_PASSWORD
# WP_URL WP_TITLE WP_ADMIN_USER WP_ADMIN_PASSWORD WP_ADMIN_EMAIL
# (optional) WP_USER WP_USER_PASSWORD WP_USER_EMAIL

PHP_FPM_BIN="php-fpm82"
DOCROOT="/var/www/html"

echo "[setup] Ensuring ownership for ${DOCROOT}"
chown -R nobody:nogroup "${DOCROOT}"

cd "${DOCROOT}"

# If bind-mounted empty dir hides image content, download core
if [ ! -f "wp-includes/version.php" ] && [ ! -f "wp-login.php" ]; then
  echo "[setup] WordPress core not found → downloading..."
  wp core download --path="${DOCROOT}" --force --allow-root
fi

# Create wp-config.php if missing
if [ ! -f "wp-config.php" ]; then
  echo "[setup] Creating wp-config.php"
  wp config create \
    --dbname="${DB_NAME}" \
    --dbuser="${DB_USER}" \
    --dbpass="${DB_PASSWORD}" \
    --dbhost="${DB_HOST}" \
    --skip-check \
    --allow-root
  # Harden a bit
  wp config set FS_METHOD direct --allow-root
fi

# Wait for DB (simple loop; replace with proper wait-for if you prefer)
echo "[setup] Waiting for database at ${DB_HOST}..."
for i in {1..30}; do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "[setup] Database is reachable."
    break
  fi
  sleep 1
done

# Install WP if not installed
if ! wp core is-installed --allow-root >/dev/null 2>&1; then
  echo "[setup] Running wp core install"
  wp core install \
    --url="${WP_URL}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email \
    --allow-root
fi

# Optional regular user
if [ -n "${WP_USER:-}" ] && ! wp user get "${WP_USER}" --allow-root >/dev/null 2>&1; then
  echo "[setup] Creating user ${WP_USER}"
  wp user create "${WP_USER}" "${WP_USER_EMAIL}" --user_pass="${WP_USER_PASSWORD}" --role=author --allow-root
fi

# Make sure URLs are correct (prevents /wp-login.php redirect weirdness)
if [ -n "${WP_URL:-}" ]; then
  current_home=$(wp option get home --allow-root || echo "")
  current_siteurl=$(wp option get siteurl --allow-root || echo "")
  if [ "${current_home}" != "${WP_URL}" ] || [ "${current_siteurl}" != "${WP_URL}" ]; then
    echo "[setup] Aligning siteurl/home to ${WP_URL}"
    wp option update home "${WP_URL}" --allow-root
    wp option update siteurl "${WP_URL}" --allow-root
  fi
fi

# Final permissions (php-fpm can read/write uploads)
find "${DOCROOT}" -type d -exec chmod 755 {} \;
find "${DOCROOT}" -type f -exec chmod 644 {} \;
chown -R nobody:nogroup "${DOCROOT}"

echo "[setup] Starting PHP-FPM in foreground"
exec ${PHP_FPM_BIN} -F
