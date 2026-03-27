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
MIN_SUBTOTAL_VALUE="${MIN_SUBTOTAL_VALUE:-1000}"
RESET_SUBTOTAL_VALUE="${RESET_SUBTOTAL_VALUE:-0}"
MIN_SUBTOTAL_INCLUDING_TAX="${MIN_SUBTOTAL_INCLUDING_TAX:-false}"
RESET_SUBTOTAL_INCLUDING_TAX="${RESET_SUBTOTAL_INCLUDING_TAX:-false}"
MIN_TOTAL_VALUE="${MIN_TOTAL_VALUE:-2000}"
RESET_TOTAL_VALUE="${RESET_TOTAL_VALUE:-0}"
K6_IMAGE="${K6_IMAGE:-grafana/k6:0.49.0}"
K6_FIXED_VUS="${K6_FIXED_VUS:-1}"
K6_FIXED_DURATION="${K6_FIXED_DURATION:-3m}"
INTERVAL_FAILURE_PHASE_DURATION="${INTERVAL_FAILURE_PHASE_DURATION:-90s}"
SECOND_FAILURE_PHASE_DURATION="${SECOND_FAILURE_PHASE_DURATION:-90s}"
PAYMENT_METHOD="${PAYMENT_METHOD:-Payments.Manual}"
THINK_TIME_SECONDS="${THINK_TIME_SECONDS:-2}"
ADD_TO_CART_PATH="${ADD_TO_CART_PATH:-}"
REALISTIC_ADD_TO_CART_PATH="${REALISTIC_ADD_TO_CART_PATH:-/addproducttocart/catalog/5/1/1}"
FAILURE_ADD_TO_CART_PATH="${FAILURE_ADD_TO_CART_PATH:-/addproducttocart/catalog/18/1/1}"
CHECKOUT_COUNTRY_ID="${CHECKOUT_COUNTRY_ID:-}"
CHECKOUT_STATE_ID="${CHECKOUT_STATE_ID:-}"
WORKDIR="${WORKDIR:-$(pwd)}"
K6_SCRIPTS_DIR="${K6_SCRIPTS_DIR:-${WORKDIR}/assessment/load-test/k6}"

bool_to_sql() {
  local value="${1,,}"
  if [[ "${value}" == "true" || "${value}" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

update_order_limits() {
  local subtotal_value="$1"
  local including_tax="$2"
  local total_value="$3"

  docker exec "${DB_CONTAINER_NAME}" /opt/mssql-tools18/bin/sqlcmd \
    -C \
    -S localhost \
    -U "${DB_USER}" \
    -P "${DB_PASSWORD}" \
    -d "${DB_NAME}" \
    -Q "UPDATE [Setting] SET [Value] = '${subtotal_value}' WHERE [Name] = 'ordersettings.minordersubtotalamount';
        UPDATE [Setting] SET [Value] = '$(bool_to_sql "${including_tax}")' WHERE [Name] = 'ordersettings.minordersubtotalamountincludingtax';
        UPDATE [Setting] SET [Value] = '${total_value}' WHERE [Name] = 'ordersettings.minordertotalamount';"
}

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
  update_order_limits "${RESET_SUBTOTAL_VALUE}" "${RESET_SUBTOTAL_INCLUDING_TAX}" "${RESET_TOTAL_VALUE}" || true
  update_min_interval "${RESET_INTERVAL_VALUE}" || true
  docker restart "${APP_CONTAINER_NAME}" >/dev/null 2>&1 || true
  wait_for_store || true
}

trap restore_setting EXIT

echo "Phase 1: setting minimum order subtotal to ${MIN_SUBTOTAL_VALUE}, minimum order total to 0, and minimum interval to 0..."
update_order_limits "${MIN_SUBTOTAL_VALUE}" "${MIN_SUBTOTAL_INCLUDING_TAX}" "0"
update_min_interval "0"

echo "Restarting application container so the new setting is picked up..."
docker restart "${APP_CONTAINER_NAME}" >/dev/null
wait_for_store

echo "Running minimum-order-subtotal failure load..."

docker run --rm --network host \
  -e BASE_URL="${BASE_URL}" \
  -e PAYMENT_METHOD="${PAYMENT_METHOD}" \
  -e THINK_TIME_SECONDS="${THINK_TIME_SECONDS}" \
  -e K6_FIXED_VUS="${K6_FIXED_VUS}" \
  -e K6_FIXED_DURATION="${K6_FIXED_DURATION}" \
  -e REALISTIC_ADD_TO_CART_PATH="${REALISTIC_ADD_TO_CART_PATH}" \
  -e FAILURE_ADD_TO_CART_PATH="${FAILURE_ADD_TO_CART_PATH}" \
  ${ADD_TO_CART_PATH:+-e ADD_TO_CART_PATH="${ADD_TO_CART_PATH}"} \
  ${CHECKOUT_COUNTRY_ID:+-e CHECKOUT_COUNTRY_ID="${CHECKOUT_COUNTRY_ID}"} \
  ${CHECKOUT_STATE_ID:+-e CHECKOUT_STATE_ID="${CHECKOUT_STATE_ID}"} \
  -v "${K6_SCRIPTS_DIR}:/scripts" \
  "${K6_IMAGE}" run /scripts/checkout-subtotal-failure.js

echo "Phase 2: setting minimum order subtotal to 0, minimum order total to 0, and minimum interval to ${MIN_INTERVAL_VALUE}..."
update_order_limits "0" "${MIN_SUBTOTAL_INCLUDING_TAX}" "0"
update_min_interval "${MIN_INTERVAL_VALUE}"

echo "Restarting application container so the new setting is picked up..."
docker restart "${APP_CONTAINER_NAME}" >/dev/null
wait_for_store

echo "Running minimum-interval failure load..."

docker run --rm --network host \
  -e BASE_URL="${BASE_URL}" \
  -e PAYMENT_METHOD="${PAYMENT_METHOD}" \
  -e THINK_TIME_SECONDS="0" \
  -e K6_FIXED_VUS="${K6_FIXED_VUS}" \
  -e K6_FIXED_DURATION="${INTERVAL_FAILURE_PHASE_DURATION}" \
  -e ADD_TO_CART_PATH="${REALISTIC_ADD_TO_CART_PATH}" \
  ${CHECKOUT_COUNTRY_ID:+-e CHECKOUT_COUNTRY_ID="${CHECKOUT_COUNTRY_ID}"} \
  ${CHECKOUT_STATE_ID:+-e CHECKOUT_STATE_ID="${CHECKOUT_STATE_ID}"} \
  -v "${K6_SCRIPTS_DIR}:/scripts" \
  "${K6_IMAGE}" run /scripts/checkout-observability-steady.js

echo "Phase 3: setting minimum order subtotal to 0, minimum order total to ${MIN_TOTAL_VALUE}, and minimum interval to 0..."
update_order_limits "0" "${MIN_SUBTOTAL_INCLUDING_TAX}" "${MIN_TOTAL_VALUE}"
update_min_interval "0"

echo "Restarting application container so the new setting is picked up..."
docker restart "${APP_CONTAINER_NAME}" >/dev/null
wait_for_store

echo "Running minimum-order-total failure load..."

docker run --rm --network host \
  -e BASE_URL="${BASE_URL}" \
  -e PAYMENT_METHOD="${PAYMENT_METHOD}" \
  -e THINK_TIME_SECONDS="${THINK_TIME_SECONDS}" \
  -e K6_FIXED_VUS="${K6_FIXED_VUS}" \
  -e K6_FIXED_DURATION="${SECOND_FAILURE_PHASE_DURATION}" \
  -e ADD_TO_CART_PATH="${FAILURE_ADD_TO_CART_PATH}" \
  ${CHECKOUT_COUNTRY_ID:+-e CHECKOUT_COUNTRY_ID="${CHECKOUT_COUNTRY_ID}"} \
  ${CHECKOUT_STATE_ID:+-e CHECKOUT_STATE_ID="${CHECKOUT_STATE_ID}"} \
  -v "${K6_SCRIPTS_DIR}:/scripts" \
  "${K6_IMAGE}" run /scripts/checkout-business-failure.js
