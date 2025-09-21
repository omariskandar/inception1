#!/usr/bin/env bash
# WordPress bootstrapper for Docker (Alpine PHP 8.2)
# - Idempotent: safe to run on each container start
# - Secrets: supports *_FILE envs and mounted ./secrets/*.txt
# - Fixes classic /wp-login.php issues by reconciling admin user/pass & URLs

set -euo pipefail

PHP_FPM_BIN="php-fpm82"
DOCROOT="/var/www/html"
SECRETS_DIR="${SECRETS_DIR:-/secrets}"
export WP_CLI_ALLOW_ROOT=1

# --------------------------- helpers --------------------------- #
get_secret() {
  # get_secret <file_path> [fallback_value]
  local file="${1:-}" fallback="${2:-}"
  if [ -n "$file" ] && [ -f "$file" ]; then
    tr -d '\r\n' < "$file"
  else
    printf '%s' "$fallback" | tr -d '\r\n'
  fi
}

maybe_from_file() {
  # maybe_from_file VAR  → if VAR_FILE is set, read it into VAR
  local var="$1" file_var="${1}_FILE"
  eval "local fp=\${$file_var:-}"
  if [ -n "$fp" ] && [ -f "$fp" ]; then
    eval "export $var=\"\$(get_secret \"$fp\")\""
  fi
}

require_var() {
  local name="$1"
  eval "local val=\"\${$name:-}\""
  if [ -z "$val" ]; then
    echo "[setup] ERROR: required variable '$name' is missing"; exit 1
  fi
}

normalize_url() {
  # remove trailing slash
  printf '%s' "${1%/}"
}

# ------------------------ absorb secrets ----------------------- #
# 1) *_FILE envs
maybe_from_file DB_PASSWORD
maybe_from_file WP_ADMIN_PASSWORD
maybe_from_file WP_USER_PASSWORD

# 2) mounted /secrets/*.txt (optional, harmless if absent)
if [ -d "$SECRETS_DIR" ]; then
  DB_PASSWORD="$(get_secret "$SECRETS_DIR/db_password.txt" "${DB_PASSWORD:-}")"
  WP_ADMIN_PASSWORD="$(get_secret "$SECRETS_DIR/wp_admin_password.txt" "${WP_ADMIN_PASSWORD:-}")"
  WP_USER_PASSWORD="$(get_secret "$SECRETS_DIR/wp_user_password.txt" "${WP_USER_PASSWORD:-}")"
fi

# ------------------------ required inputs ---------------------- #
require_var DB_HOST
require_var DB_NAME
require_var DB_USER
require_var WP_URL
require_var WP_TITLE
require_var WP_ADMIN_USER
require_var WP_ADMIN_EMAIL
require_var WP_ADMIN_PASSWORD

# normalize URL (no trailing slash)
WP_URL="$(normalize_url "$WP_URL")"

# --------------------- pre-flight & ownership ------------------ #
if ! command -v wp >/dev/null 2>&1; then
  echo "[setup] ERROR: wp-cli is not installed in the image"; exit 1
fi

mkdir -p "$DOCROOT"
echo "[setup] Ensuring ownership for ${DOCROOT}"
chown -R nobody:nogroup "$DOCROOT"

cd "$DOCROOT"

# Download core if bind-mount hid image content
if [ ! -f "wp-includes/version.php" ] && [ ! -f "wp-login.php" ]; then
  echo "[setup] WordPress core not found → downloading..."
  wp core download --path="$DOCROOT" --force --allow-root
fi

# Create wp-config.php if missing
if [ ! -f "wp-config.php" ]; then
  echo "[setup] Creating wp-config.php"
  wp config create \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASSWORD" \
    --dbhost="$DB_HOST" \
    --skip-check \
    --allow-root

  # file system method & salts (optional hardening)
  wp config set FS_METHOD direct --allow-root
  # add salts only if not present
  if ! grep -q "AUTH_KEY" wp-config.php 2>/dev/null; then
    wp config shuffle-salts --allow-root || true
  fi
fi

# ------------------------- wait for DB ------------------------- #
echo "[setup] Waiting for database at ${DB_HOST}..."
for i in $(seq 1 60); do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "[setup] Database is reachable."
    break
  fi
  sleep 1
  [ "$i" -eq 60 ] && { echo "[setup] ERROR: database not reachable"; exit 1; }
done

# --------------------- install / reconcile --------------------- #
if ! wp core is-installed --allow-root >/dev/null 2>&1; then
  echo "[setup] Running wp core install"
  wp core install \
    --url="$WP_URL" \
    --title="$WP_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --skip-email \
    --allow-root
else
  echo "[setup] Core already installed — reconciling admin user & password"
  if wp user get "$WP_ADMIN_USER" --field=ID --allow-root >/dev/null 2>&1; then
    # ensure the intended admin password is set (newline-safe from secrets)
    wp user update "$WP_ADMIN_USER" --user_pass="$WP_ADMIN_PASSWORD" --allow-root
    # ensure role includes administrator
    if ! wp user list --role=administrator --field=user_login --allow-root | grep -qx "$WP_ADMIN_USER"; then
      wp user set-role "$WP_ADMIN_USER" administrator --allow-root
    fi
  else
    # If admin with different login exists, keep it; also ensure at least one admin exists.
    if ! wp user list --role=administrator --field=user_login --allow-root | grep -q .; then
      echo "[setup] No admin found — creating ${WP_ADMIN_USER}"
      wp user create "$WP_ADMIN_USER" "$WP_ADMIN_EMAIL" \
        --user_pass="$WP_ADMIN_PASSWORD" --role=administrator --allow-root
    fi
  fi
fi

# Optional regular user (idempotent)
if [ -n "${WP_USER:-}" ]; then
  if wp user get "$WP_USER" --allow-root >/dev/null 2>&1; then
    [ -n "${WP_USER_PASSWORD:-}" ] && wp user update "$WP_USER" --user_pass="$WP_USER_PASSWORD" --allow-root
  else
    require_var WP_USER_EMAIL
    echo "[setup] Creating user ${WP_USER}"
    wp user create "$WP_USER" "$WP_USER_EMAIL" \
      --user_pass="${WP_USER_PASSWORD:-$(openssl rand -hex 12 2>/dev/null || echo tempPass123!)}" \
      --role=author --allow-root
  fi
fi

# Ensure URLs are correct (prevents /wp-login.php redirect issues)
current_home="$(wp option get home --allow-root || true)"
current_siteurl="$(wp option get siteurl --allow-root || true)"
if [ "$current_home" != "$WP_URL" ] || [ "$current_siteurl" != "$WP_URL" ]; then
  echo "[setup] Aligning siteurl/home to ${WP_URL}"
  wp option update home "$WP_URL" --allow-root
  wp option update siteurl "$WP_URL" --allow-root
fi

# Force SSL admin if URL is https
case "$WP_URL" in
  https://*) wp config set FORCE_SSL_ADMIN true --type=constant --allow-root || true ;;
esac

# -------------------------- permissions ------------------------ #
find "$DOCROOT" -type d -exec chmod 755 {} \;
find "$DOCROOT" -type f -exec chmod 644 {} \;
chown -R nobody:nogroup "$DOCROOT"

# ----------------------- start php-fpm ------------------------- #
echo "[setup] Starting PHP-FPM (${PHP_FPM_BIN}) in foreground"
exec "$PHP_FPM_BIN" -F
