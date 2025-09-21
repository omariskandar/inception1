#!/bin/bash
set -euo pipefail

# ----- Read env variables -----
MYSQL_HOST="${MYSQL_HOST:?}"
MYSQL_PORT="${MYSQL_PORT:?}"
MYSQL_DATABASE="${MYSQL_DATABASE:?}"
MYSQL_USER="${MYSQL_USER:?}"
DB_PASS=$(cat "${MYSQL_PASSWORD_FILE}")

WP_TITLE="${WP_TITLE:?}"
WP_URL="${WP_URL:?}"
WP_ADMIN_USER="${WP_ADMIN_USER:?}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:?}"
WP_ADMIN_PASS=$(cat "${WP_ADMIN_PASSWORD_FILE}")
WP_USER="${WP_USER:?}"
WP_USER_EMAIL="${WP_USER_EMAIL:?}"
WP_USER_PASS=$(cat "${WP_USER_PASSWORD_FILE}")

# Wait for database
echo "Waiting for database..."
for i in {1..20}; do
  if mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Database connected!"
    break
  fi
  sleep 3
done

# Basic WordPress setup
if [ ! -f "wp-includes/version.php" ]; then
  echo "Downloading WordPress..."
  curl -fsSL https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1
fi

if [ ! -f "wp-config.php" ]; then
  echo "Creating wp-config.php..."
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/${MYSQL_DATABASE}/g" wp-config.php
  sed -i "s/username_here/${MYSQL_USER}/g" wp-config.php
  sed -i "s/password_here/${DB_PASS}/g" wp-config.php
  sed -i "s/localhost/${MYSQL_HOST}:${MYSQL_PORT}/g" wp-config.php
fi

# ----- Check if WordPress is already installed -----
if wp core is-installed --allow-root 2>/dev/null; then
  echo "WordPress is already installed."
  
  # Ensure URLs are correct
  echo "Updating site URLs..."
  wp option update siteurl "${WP_URL}" --allow-root
  wp option update home "${WP_URL}" --allow-root
  
  # Update or create admin user
  if wp user get "${WP_ADMIN_USER}" --field=id --allow-root 2>/dev/null; then
    echo "Updating admin user: ${WP_ADMIN_USER}"
    wp user update "${WP_ADMIN_USER}" --user_pass="${WP_ADMIN_PASS}" --role=administrator --allow-root
  else
    echo "Creating admin user: ${WP_ADMIN_USER}"
    wp user create "${WP_ADMIN_USER}" "${WP_ADMIN_EMAIL}" --role=administrator --user_pass="${WP_ADMIN_PASS}" --allow-root
  fi
  
  # Update or create regular user
  if wp user get "${WP_USER}" --field=id --allow-root 2>/dev/null; then
    echo "Updating regular user: ${WP_USER}"
    wp user update "${WP_USER}" --user_pass="${WP_USER_PASS}" --role=subscriber --allow-root
  else
    echo "Creating regular user: ${WP_USER}"
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" --role=subscriber --user_pass="${WP_USER_PASS}" --allow-root
  fi
  
else
  # ----- Install WordPress (only if not installed) -----
  echo "Installing WordPress..."
  wp core install \
    --url="${WP_URL}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email \
    --allow-root

  # Update site URLs
  wp option update siteurl "${WP_URL}" --allow-root
  wp option update home "${WP_URL}" --allow-root

  # Create additional user
  echo "Creating regular user: ${WP_USER}"
  wp user create "${WP_USER}" "${WP_USER_EMAIL}" --role=subscriber --user_pass="${WP_USER_PASS}" --allow-root
fi

# Set permissions
chown -R nobody:nogroup /var/www/html
chmod -R 755 /var/www/html

echo "Starting PHP-FPM..."
exec php-fpm82 -F