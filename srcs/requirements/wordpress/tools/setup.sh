#!/usr/bin/env bash
set -euo pipefail

PHP_FPM_BIN="php-fpm82"
DOCROOT="/var/www/html"
export WP_CLI_ALLOW_ROOT=1

# --- helpers ---------------------------------------------------------------
# Prefer Docker secrets/ mounted files; fall back to env var.
# Strips CR/LF so passwords coming from text files are clean.
get_secret() {
  # usage: get_secret <file_path> [fallback_env_value]
  local file="${1:-}"; local fallback="${2:-}"
  if [ -n "$file" ] && [ -f "$file" ]; then
    tr -d '\r\n' < "$file"
  else
    printf '%s' "$fallback" | tr -d '\r\n'
  fi
}

# Optionally support *_FILE pattern used by Docker
maybe_from_file() {
  # usage: maybe_from_file VAR
  # if VAR_FILE is set, read from it into VAR
  local var="$1" file_var="${1}_FILE"
  eval "local file_path=\"\${$file_var:-}\""
  if [ -n "${file_path}" ] && [ -f "${file_path}" ]; then
    eval "export $var=\"$(get_secret "${file_path}")\""
  fi
}

# --- normalize inputs ------------------------------------------------------
# If you pass *_FILE in compose, absorb them:
maybe_from_file DB_PASSWORD
maybe_from_file WP_ADMIN_PASSWORD
maybe_from_file WP_USER_PASSWORD

# Or read from your mounted secrets directory if you prefer:
: "${SECRETS_DIR:=/secrets}"  # adjust if you mount it elsewhere
if [ -d "${SECRETS_DIR}" ]; then
  DB_PASSWORD="$(get_secret "${SECRETS_DIR}/db_password.txt" "${DB_PASSWORD:-}")"
  WP_ADMIN_PASSWORD="$(get_secret "${SECRETS_DIR}/wp_admin_password.txt" "${WP_ADMIN_PASSWORD:-}")"
  WP_USER_PASSWORD="$(get_secret "${SECRETS_DIR}/wp_user_password.txt" "${WP_USER_PASSWORD:-}")"
fi

# Basic presence checks (don’t crash if user password optional)
: "${DB_HOST:?DB_HOST missing}"
: "${DB_NAME:?DB_NAME missing}"
: "${DB_USER:?DB_USER missing}"
: "${WP_URL:?WP_URL missing}"
: "${WP_TITLE:?WP_TITLE missing}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER missing}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL missing}"
: "${WP_ADMIN_PASSWORD:?WP_ADMIN_PASSWORD missing or unreadable}"

echo "[setup] Ensuring ownership for ${DOCROOT}"
chown -R nobody:nogroup "${DOCROOT}"

cd "${DOCROOT}"

# Download core if hidden by an empty bind mount
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
  wp config set FS_METHOD direct --allow-root
fi

# Wait for DB
echo "[setup] Waiting for database at ${DB_HOST}..."
for i in {1..60}; do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "[setup] Database is reachable."
    break
  fi
  sleep 1
done

# Install or reconcile admin user deterministically
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
else
  echo "[setup] Core already installed — reconciling admin user + password"
  # If admin user exists but has a different login, align to WP_ADMIN_USER
  # (common when you originally installed with a different name)
  if wp user get "${WP_ADMIN_USER}" --field=ID --allow-root >/dev/null 2>&1; then
    # user exists → ensure password is the one from secret (newline-free)
    wp user update "${WP_ADMIN_USER}" --user_pass="${WP_ADMIN_PASSWORD}" --allow-root
  else
    # No such user → ensure there is at least one admin. If none, create ours.
    if ! wp user list --role=administrator --field=user_login --allow-root | grep -q .; then
      echo "[setup] No admin found — creating ${WP_ADMIN_USER}"
      wp user create "${WP_ADMIN_USER}" "${WP_ADMIN_EMAIL}" \
        --user_pass="${WP_ADMIN_PASSWORD}" --role=administrator --allow-root
    fi
  fi
fi

# Optional regular user
if [ -n "${WP_USER:-}" ]; then
  if wp user get "${WP_USER}" --allow-root >/dev/null 2>&1; then
    [ -n "${WP_USER_PASSWORD:-}" ] && wp user update "${WP_USER}" --user_pass="${WP_USER_PASSWORD}" --allow-root
  else
    echo "[setup] Creating user ${WP_USER}"
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
      --user_pass="${WP_USER_PASSWORD}" --role=author --allow-root
  fi
fi

# Ensure URLs are correct (prevents redirect weirdness on /wp-login.php)
current_home=$(wp option get home --allow-root || echo "")
current_siteurl=$(wp option get siteurl --allow-root || echo "")
if [ "${current_home}" != "${WP_URL}" ] || [ "${current_siteurl}" != "${WP_URL}" ]; then
  echo "[setup] Aligning siteurl/home to ${WP_URL}"
  wp option update home "${WP_URL}" --allow-root
  wp option update siteurl "${WP_URL}" --allow-root
fi

# Permissions
find "${DOCROOT}" -type d -exec chmod 755 {} \;
find "${DOCROOT}" -type f -exec chmod 644 {} \;
chown -R nobody:nogroup "${DOCROOT}"

echo "[setup] Starting PHP-FPM in foreground"
exec ${PHP_FPM_BIN} -F
