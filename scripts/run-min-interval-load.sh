#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
APP_CONTAINER_NAME="${APP_CONTAINER_NAME:-nopcommerce}"
DB_CONTAINER_NAME="${DB_CONTAINER_NAME:-nopcommerce_mssql_server}"
DB_NAME="${INSTALL_DB_NAME:-nopCommerce}"
DB_USER="${INSTALL_DB_USER:-sa}"
DB_PASSWORD="${INSTALL_DB_PASSWORD:-nopCommerce_db_password}"
MIN_INTERVAL_VALUE="${MIN_INTERVAL_VALUE:-5}"
RESET_INTERVAL_VALUE="${RESET_INTERVAL_VALUE:-1}"
K6_IMAGE="${K6_IMAGE:-grafana/k6:0.49.0}"
K6_FIXED_VUS="${K6_FIXED_VUS:-1}"
K6_FIXED_DURATION="${K6_FIXED_DURATION:-90s}"
PAYMENT_METHOD="${PAYMENT_METHOD:-Payments.CheckMoneyOrder}"
THINK_TIME_SECONDS="${THINK_TIME_SECONDS:-0}"
ADD_TO_CART_PATH="${ADD_TO_CART_PATH:-}"
CHECKOUT_COUNTRY_ID="${CHECKOUT_COUNTRY_ID:-}"
CHECKOUT_STATE_ID="${CHECKOUT_STATE_ID:-}"
WORKDIR="${WORKDIR:-$(pwd)}"

update_min_interval() {
  local value="$1"

  docker exec "${DB_CONTAINER_NAME}" /opt/mssql-tools18/bin/sqlcmd \
    -C \
    -S localhost \
    -U "${DB_USER}" \
    -P "${DB_PASSWORD}" \
    -d "${DB_NAME}" \
    -Q "UPDATE [Setting] SET [Value] = '${value}' WHERE [Name] = 'ordersettings.minimumorderplacementinterval';"
}

wait_for_store() {
  local attempts=60

  while (( attempts > 0 )); do
    if curl -fsS -L "${BASE_URL}" >/dev/null 2>&1; then
      return 0
    fi

    attempts=$((attempts - 1))
    sleep 2
  done

  echo "Timed out waiting for the store to become ready." >&2
  return 1
}

restore_setting() {
  update_min_interval "${RESET_INTERVAL_VALUE}" || true
  docker restart "${APP_CONTAINER_NAME}" >/dev/null 2>&1 || true
  wait_for_store || true
}

trap restore_setting EXIT

echo "Setting minimum order placement interval to ${MIN_INTERVAL_VALUE} minutes..."
update_min_interval "${MIN_INTERVAL_VALUE}"

echo "Restarting application container so the new setting is picked up..."
docker restart "${APP_CONTAINER_NAME}" >/dev/null
wait_for_store

echo "Running controlled minimum-interval failure load..."

docker run --rm --network host \
  -e BASE_URL="${BASE_URL}" \
  -e PAYMENT_METHOD="${PAYMENT_METHOD}" \
  -e THINK_TIME_SECONDS="${THINK_TIME_SECONDS}" \
  -e K6_FIXED_VUS="${K6_FIXED_VUS}" \
  -e K6_FIXED_DURATION="${K6_FIXED_DURATION}" \
  ${ADD_TO_CART_PATH:+-e ADD_TO_CART_PATH="${ADD_TO_CART_PATH}"} \
  ${CHECKOUT_COUNTRY_ID:+-e CHECKOUT_COUNTRY_ID="${CHECKOUT_COUNTRY_ID}"} \
  ${CHECKOUT_STATE_ID:+-e CHECKOUT_STATE_ID="${CHECKOUT_STATE_ID}"} \
  -v "${WORKDIR}/loadtests/k6:/scripts" \
  "${K6_IMAGE}" run /scripts/checkout-observability-steady.js
