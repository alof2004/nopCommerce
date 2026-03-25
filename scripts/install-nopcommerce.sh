#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
BASE_URL="${BASE_URL%/}"

ADMIN_EMAIL="${INSTALL_ADMIN_EMAIL:-admin@yourStore.com}"
ADMIN_PASSWORD="${INSTALL_ADMIN_PASSWORD:-Admin123!}"
INSTALL_SAMPLE_DATA="${INSTALL_SAMPLE_DATA:-true}"
SUBSCRIBE_NEWSLETTERS="${SUBSCRIBE_NEWSLETTERS:-false}"
COUNTRY="${INSTALL_COUNTRY:-}"

DB_SERVER="${INSTALL_DB_SERVER:-nopcommerce_database}"
DB_NAME="${INSTALL_DB_NAME:-nopCommerce}"
DB_USER="${INSTALL_DB_USER:-sa}"
DB_PASSWORD="${INSTALL_DB_PASSWORD:-nopCommerce_db_password}"
CREATE_DATABASE="${CREATE_DATABASE_IF_NOT_EXISTS:-true}"
MIN_ORDER_SUBTOTAL="${INSTALL_MIN_ORDER_SUBTOTAL:-}"
MIN_ORDER_SUBTOTAL_INCLUDING_TAX="${INSTALL_MIN_ORDER_SUBTOTAL_INCLUDING_TAX:-false}"

COMPOSE_CMD="${COMPOSE_CMD:-docker compose -f docker-compose.yml -f docker-compose.observability.yml}"
APP_CONTAINER_NAME="${APP_CONTAINER_NAME:-nopcommerce}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cookie_jar="$work_dir/cookies.txt"
install_page="$work_dir/install.html"
install_result="$work_dir/install-result.html"

bool_to_form() {
  local value="${1,,}"
  case "$value" in
    true|1|yes|on) printf "true" ;;
    *) printf "false" ;;
  esac
}

extract_token() {
  perl -ne 'if (/name="__RequestVerificationToken"[^>]*value="([^"]+)"/) { print $1; exit 0 }' "$1"
}

extract_selected_country() {
  perl -0ne '
    if (/<select[^>]*id="Country"[^>]*>(.*?)<\/select>/s) {
      my $block = $1;
      if ($block =~ /<option[^>]*selected="selected"[^>]*value="([^"]*)"/s) {
        print $1;
      }
    }
  ' "$1"
}

get_container_status() {
  docker inspect -f '{{.State.Status}}' "$APP_CONTAINER_NAME" 2>/dev/null || true
}

run_sql() {
  local query="$1"

  docker exec nopcommerce_mssql_server /opt/mssql-tools18/bin/sqlcmd -C \
    -S localhost \
    -U "$DB_USER" \
    -P "$DB_PASSWORD" \
    -d "$DB_NAME" \
    -Q "$query" >/dev/null
}

ensure_app_container_running() {
  local status
  status="$(get_container_status)"

  if [[ -z "$status" ]]; then
    echo "App container '$APP_CONTAINER_NAME' was not found." >&2
    exit 1
  fi

  if [[ "$status" != "running" ]]; then
    docker start "$APP_CONTAINER_NAME" >/dev/null
  fi
}

echo "Fetching install page..."
for attempt in $(seq 1 60); do
  if curl -fsS -c "$cookie_jar" "$BASE_URL/install" -o "$install_page" 2>/dev/null; then
    break
  fi
  sleep 2
done

if [[ ! -s "$install_page" ]]; then
  echo "Timed out waiting for the install page to become available." >&2
  exit 1
fi

if ! grep -qi "nopCommerce installation" "$install_page"; then
  echo "Install page is not active. The store may already be installed."
  exit 0
fi

token="$(extract_token "$install_page")"
if [[ -z "$token" ]]; then
  echo "Could not extract anti-forgery token from install page." >&2
  exit 1
fi

if [[ -z "$COUNTRY" ]]; then
  COUNTRY="$(extract_selected_country "$install_page")"
fi

echo "Submitting nopCommerce installation..."
curl -fsS -b "$cookie_jar" -c "$cookie_jar" \
  -X POST "$BASE_URL/install" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "__RequestVerificationToken=$token" \
  --data-urlencode "AdminEmail=$ADMIN_EMAIL" \
  --data-urlencode "AdminPassword=$ADMIN_PASSWORD" \
  --data-urlencode "ConfirmPassword=$ADMIN_PASSWORD" \
  --data-urlencode "UseCustomCollation=false" \
  --data-urlencode "Collation=" \
  --data-urlencode "CharacterSet=" \
  --data-urlencode "CreateDatabaseIfNotExists=$(bool_to_form "$CREATE_DATABASE")" \
  --data-urlencode "InstallSampleData=$(bool_to_form "$INSTALL_SAMPLE_DATA")" \
  --data-urlencode "ConnectionStringRaw=false" \
  --data-urlencode "InstallRegionalResources=true" \
  --data-urlencode "SubscribeNewsletters=$(bool_to_form "$SUBSCRIBE_NEWSLETTERS")" \
  --data-urlencode "DatabaseName=$DB_NAME" \
  --data-urlencode "ServerName=$DB_SERVER" \
  --data-urlencode "IntegratedSecurity=false" \
  --data-urlencode "Username=$DB_USER" \
  --data-urlencode "Password=$DB_PASSWORD" \
  --data-urlencode "ConnectionString=" \
  --data-urlencode "DataProvider=1" \
  --data-urlencode "Country=$COUNTRY" \
  -o "$install_result"

if grep -qi "Setup failed:" "$install_result"; then
  echo "Install form returned an error page." >&2
  sed -n '1,220p' "$install_result" >&2
  exit 1
fi

if ! grep -q "/install/restartapplication" "$install_result"; then
  echo "Install submission did not return the expected restart page." >&2
  sed -n '1,220p' "$install_result" >&2
  exit 1
fi

echo "Triggering nopCommerce application restart..."
curl -fsS "$BASE_URL/install/restartapplication" >/dev/null || true

echo "Ensuring app container is running..."
ensure_app_container_running

echo "Waiting for store to become ready..."
for attempt in $(seq 1 60); do
  if [[ "$(get_container_status)" == "exited" ]]; then
    ensure_app_container_running
  fi

  if html="$(curl -fsS -L "$BASE_URL" 2>/dev/null)"; then
    if grep -qi "nopCommerce installation" <<<"$html"; then
      sleep 2
      continue
    fi

    if [[ -n "$MIN_ORDER_SUBTOTAL" ]]; then
      echo "Applying minimum order subtotal setting..."
      run_sql "UPDATE [Setting] SET [Value] = '${MIN_ORDER_SUBTOTAL}' WHERE [Name] = 'ordersettings.minordersubtotalamount';"
      run_sql "UPDATE [Setting] SET [Value] = '$(bool_to_form "$MIN_ORDER_SUBTOTAL_INCLUDING_TAX")' WHERE [Name] = 'ordersettings.minordersubtotalamountincludingtax';"
      docker restart "$APP_CONTAINER_NAME" >/dev/null
      ensure_app_container_running
    fi

    echo "Store installation completed successfully."
    exit 0
  fi
  sleep 2
done

echo "Timed out waiting for the store to become ready after installation." >&2
exit 1
