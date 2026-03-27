SHELL := /bin/bash

BASE_URL ?= http://localhost
PAYMENT_METHOD ?= Payments.Manual
ADD_TO_CART_PATH ?=
REALISTIC_PRODUCT_NAME ?= Asus Laptop
REALISTIC_ADD_TO_CART_PATH ?= /addproducttocart/catalog/5/1/1
FAILURE_PRODUCT_NAME ?= HTC smartphone
FAILURE_ADD_TO_CART_PATH ?= /addproducttocart/catalog/18/1/1
CHECKOUT_COUNTRY_ID ?=
CHECKOUT_STATE_ID ?=
THINK_TIME_SECONDS ?= 1
IMPATIENT_USER_PERCENT ?= 0.30
NORMAL_REQUEST_TIMEOUT ?= 10s
IMPATIENT_CONFIRM_TIMEOUT ?= 3s
K6_IMAGE ?= grafana/k6:0.49.0
K6_STAGE_1_DURATION ?= 30s
K6_STAGE_1_TARGET ?= 5
K6_STAGE_2_DURATION ?= 2m
K6_STAGE_2_TARGET ?= 10
K6_STAGE_3_DURATION ?= 3m
K6_STAGE_3_TARGET ?= 10
K6_STAGE_4_DURATION ?= 30s
K6_STAGE_4_TARGET ?= 0
K6_FIXED_VUS ?= 5
K6_FIXED_DURATION ?= 24h
MIN_INTERVAL_VALUE ?= 5
RESET_INTERVAL_VALUE ?= 1
MIN_SUBTOTAL_VALUE ?= 1000
RESET_SUBTOTAL_VALUE ?= 0
MIN_SUBTOTAL_INCLUDING_TAX ?= false
RESET_SUBTOTAL_INCLUDING_TAX ?= false
MIN_TOTAL_VALUE ?= 2000
RESET_TOTAL_VALUE ?= 0
INTERVAL_FAILURE_PHASE_DURATION ?= 90s
SECOND_FAILURE_PHASE_DURATION ?= 90s
INSTALL_ADMIN_EMAIL ?= admin@yourStore.com
INSTALL_ADMIN_PASSWORD ?= Admin123!
INSTALL_SAMPLE_DATA ?= true
INSTALL_REGIONAL_RESOURCES ?= false
SUBSCRIBE_NEWSLETTERS ?= false
INSTALL_COUNTRY ?=
INSTALL_DB_SERVER ?= nopcommerce_database
INSTALL_DB_NAME ?= nopCommerce
INSTALL_DB_USER ?= sa
INSTALL_DB_PASSWORD ?= nopCommerce_db_password
CREATE_DATABASE_IF_NOT_EXISTS ?= true
INSTALL_MIN_ORDER_SUBTOTAL ?=
INSTALL_MIN_ORDER_SUBTOTAL_INCLUDING_TAX ?= false
ASSESSMENT_DIR ?= assessment
OBSERVABILITY_DIR ?= $(ASSESSMENT_DIR)/observability
LOADTEST_DIR ?= $(ASSESSMENT_DIR)/load-test/k6

COMPOSE := docker compose -f docker-compose.yml -f docker-compose.observability.yml
COMPOSE_LOADTEST := docker compose -f docker-compose.yml -f docker-compose.observability.yml -f docker-compose.loadtest.yml
APP_CONTAINER_NAME ?= nopcommerce
K6_SCRIPTS_MOUNT := -v "$(PWD)/$(LOADTEST_DIR):/scripts"
K6_ENV := -e BASE_URL=$(BASE_URL) \
	-e PAYMENT_METHOD=$(PAYMENT_METHOD) \
	-e THINK_TIME_SECONDS=$(THINK_TIME_SECONDS) \
	-e IMPATIENT_USER_PERCENT=$(IMPATIENT_USER_PERCENT) \
	-e NORMAL_REQUEST_TIMEOUT=$(NORMAL_REQUEST_TIMEOUT) \
	-e IMPATIENT_CONFIRM_TIMEOUT=$(IMPATIENT_CONFIRM_TIMEOUT) \
	-e K6_STAGE_1_DURATION=$(K6_STAGE_1_DURATION) \
	-e K6_STAGE_1_TARGET=$(K6_STAGE_1_TARGET) \
	-e K6_STAGE_2_DURATION=$(K6_STAGE_2_DURATION) \
	-e K6_STAGE_2_TARGET=$(K6_STAGE_2_TARGET) \
	-e K6_STAGE_3_DURATION=$(K6_STAGE_3_DURATION) \
	-e K6_STAGE_3_TARGET=$(K6_STAGE_3_TARGET) \
	-e K6_STAGE_4_DURATION=$(K6_STAGE_4_DURATION) \
	-e K6_STAGE_4_TARGET=$(K6_STAGE_4_TARGET) \
	-e K6_FIXED_VUS=$(K6_FIXED_VUS) \
	-e K6_FIXED_DURATION=$(K6_FIXED_DURATION)

ifneq ($(strip $(ADD_TO_CART_PATH)),)
K6_ENV += -e ADD_TO_CART_PATH=$(ADD_TO_CART_PATH)
endif

ifneq ($(strip $(CHECKOUT_COUNTRY_ID)),)
K6_ENV += -e CHECKOUT_COUNTRY_ID=$(CHECKOUT_COUNTRY_ID)
endif

ifneq ($(strip $(CHECKOUT_STATE_ID)),)
K6_ENV += -e CHECKOUT_STATE_ID=$(CHECKOUT_STATE_ID)
endif

.PHONY: help up down restart install ps logs app-logs collector-logs grafana-logs smoke load load-steady load-5 load-20 load-30 load-50 load-100 load-min-interval load-min-interval-1000 load-min-subtotal load-min-subtotal-1000 load-realistic load-business-failure up-loadtest down-loadtest load-degrade store-status urls

help:
	@echo "Available targets:"
	@echo "  make up            Start nopCommerce + observability stack"
	@echo "  make down          Stop the stack"
	@echo "  make restart       Recreate the stack"
	@echo "  make install       Install nopCommerce through the real web install flow"
	@echo "  make ps            Show running containers"
	@echo "  make logs          Follow all compose logs"
	@echo "  make app-logs      Follow nopCommerce app logs"
	@echo "  make collector-logs Follow OpenTelemetry Collector logs"
	@echo "  make grafana-logs  Follow Grafana logs"
	@echo "  make store-status  Check whether the store is installed or still on /install"
	@echo "  make smoke         Run one checkout smoke iteration through k6"
	@echo "  make load          Run the default checkout load profile through k6"
	@echo "  make load-steady   Run a fixed-user checkout load until you stop it"
	@echo "  make load-5        Run a fixed 5-user checkout load until you stop it"
	@echo "  make load-20       Run a staged checkout profile peaking at 20 VUs"
	@echo "  make load-30       Run a staged checkout profile peaking at 30 VUs"
	@echo "  make load-50       Run a staged checkout profile peaking at 50 VUs"
	@echo "  make load-100      Run a staged checkout profile peaking at 100 VUs"
	@echo "  make load-min-interval Run a controlled failure demo using minimum order interval"
	@echo "  make load-min-interval-1000 Set minimum order interval to 1000 and run the controlled failure demo"
	@echo "  make load-min-subtotal Run a controlled failure demo using minimum order subtotal"
	@echo "  make load-min-subtotal-1000 Set minimum order subtotal/total to 1000 and run the controlled failure demo"
	@echo "  make load-realistic    Run 20 VUs with a 3s impatient confirm timeout (realistic user abandonment)"
	@echo "  make load-business-failure Run a low-noise steady checkout flow for controlled validation failures"
	@echo ""
	@echo "Realistic abandonment tuning:"
	@echo "  IMPATIENT_USER_PERCENT=0.30"
	@echo "  NORMAL_REQUEST_TIMEOUT=10s"
	@echo "  IMPATIENT_CONFIRM_TIMEOUT=3s"
	@echo ""
	@echo "Controlled degradation mode (creates interesting graphs without crashing):"
	@echo "  make up-loadtest   Start with resource constraints for controlled degradation"
	@echo "  make load-degrade  Run 15→30→40 VU profile (degrades but doesn't crash)"
	@echo "  make down-loadtest Stop the loadtest stack"
	@echo ""
	@echo "  make urls          Print local service URLs"
	@echo ""
	@echo "Optional overrides:"
	@echo "  BASE_URL=http://localhost"
	@echo "  PAYMENT_METHOD=Payments.Manual"
	@echo "  THINK_TIME_SECONDS=1"
	@echo "  K6_STAGE_1_DURATION=30s"
	@echo "  K6_STAGE_1_TARGET=5"
	@echo "  K6_STAGE_2_DURATION=2m"
	@echo "  K6_STAGE_2_TARGET=10"
	@echo "  K6_STAGE_3_DURATION=3m"
	@echo "  K6_STAGE_3_TARGET=10"
	@echo "  K6_STAGE_4_DURATION=30s"
	@echo "  K6_STAGE_4_TARGET=0"
	@echo "  K6_FIXED_VUS=5"
	@echo "  K6_FIXED_DURATION=24h"
	@echo "  MIN_INTERVAL_VALUE=5"
	@echo "  RESET_INTERVAL_VALUE=1"
	@echo "  MIN_SUBTOTAL_VALUE=1000"
	@echo "  RESET_SUBTOTAL_VALUE=0"
	@echo "  MIN_SUBTOTAL_INCLUDING_TAX=false"
	@echo "  RESET_SUBTOTAL_INCLUDING_TAX=false"
	@echo "  MIN_TOTAL_VALUE=2000"
	@echo "  RESET_TOTAL_VALUE=0"
	@echo "  SECOND_FAILURE_PHASE_DURATION=90s"
	@echo "  REALISTIC_ADD_TO_CART_PATH=/addproducttocart/catalog/5/1/1"
	@echo "  FAILURE_ADD_TO_CART_PATH=/addproducttocart/catalog/18/1/1"
	@echo "  INSTALL_ADMIN_EMAIL=admin@yourStore.com"
	@echo "  INSTALL_ADMIN_PASSWORD=Admin123!"
	@echo "  INSTALL_SAMPLE_DATA=true"
	@echo "  INSTALL_REGIONAL_RESOURCES=false"
	@echo "  INSTALL_MIN_ORDER_SUBTOTAL="
	@echo "  INSTALL_MIN_ORDER_SUBTOTAL_INCLUDING_TAX=false"
	@echo "  APP_CONTAINER_NAME=nopcommerce"
	@echo "  ADD_TO_CART_PATH=/addproducttocart/catalog/1/1/1"
	@echo "  CHECKOUT_COUNTRY_ID=1"
	@echo "  CHECKOUT_STATE_ID=0"

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) up -d --build --force-recreate

install:
	$(COMPOSE) down
	INSTALLATION_CONFIG__INSTALL_REGIONAL_RESOURCES=$(INSTALL_REGIONAL_RESOURCES) \
	$(COMPOSE) up -d --build
	BASE_URL=$(BASE_URL) \
	INSTALL_ADMIN_EMAIL=$(INSTALL_ADMIN_EMAIL) \
	INSTALL_ADMIN_PASSWORD=$(INSTALL_ADMIN_PASSWORD) \
	INSTALL_SAMPLE_DATA=$(INSTALL_SAMPLE_DATA) \
	SUBSCRIBE_NEWSLETTERS=$(SUBSCRIBE_NEWSLETTERS) \
	INSTALL_COUNTRY=$(INSTALL_COUNTRY) \
	INSTALL_DB_SERVER=$(INSTALL_DB_SERVER) \
	INSTALL_DB_NAME=$(INSTALL_DB_NAME) \
	INSTALL_DB_USER=$(INSTALL_DB_USER) \
	INSTALL_DB_PASSWORD=$(INSTALL_DB_PASSWORD) \
	CREATE_DATABASE_IF_NOT_EXISTS=$(CREATE_DATABASE_IF_NOT_EXISTS) \
	INSTALL_MIN_ORDER_SUBTOTAL=$(INSTALL_MIN_ORDER_SUBTOTAL) \
	INSTALL_MIN_ORDER_SUBTOTAL_INCLUDING_TAX=$(INSTALL_MIN_ORDER_SUBTOTAL_INCLUDING_TAX) \
	COMPOSE_CMD='$(COMPOSE)' \
	APP_CONTAINER_NAME=$(APP_CONTAINER_NAME) \
	bash ./scripts/install-nopcommerce.sh

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

app-logs:
	docker logs -f nopcommerce

collector-logs:
	$(COMPOSE) logs -f otel-collector

grafana-logs:
	$(COMPOSE) logs -f grafana

store-status:
	@status="$$(curl -fsS -L $(BASE_URL) 2>/dev/null | head -n 20 || true)"; \
	if [ -z "$$status" ]; then \
		echo "Store status: UNREACHABLE"; \
		exit 1; \
	fi; \
	if echo "$$status" | grep -qi "nopCommerce installation"; then \
		echo "Store status: NOT INSTALLED (/install is active)"; \
	else \
		echo "Store status: READY"; \
	fi

smoke:
	docker run --rm --network host \
		$(K6_ENV) \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run --vus 1 --iterations 1 /scripts/checkout-observability.js

load:
	docker run --rm --network host \
		$(K6_ENV) \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability.js

load-steady:
	docker run --rm --network host \
		$(K6_ENV) \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability-steady.js

load-5:
	docker run --rm --network host \
		$(K6_ENV) \
		-e K6_FIXED_VUS=5 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability-steady.js

load-20:
	docker run --rm --network host \
		$(K6_ENV) \
		-e K6_STAGE_1_TARGET=5 \
		-e K6_STAGE_2_TARGET=10 \
		-e K6_STAGE_3_TARGET=20 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability.js

load-30:
	docker run --rm --network host \
		$(K6_ENV) \
		-e K6_STAGE_1_TARGET=10 \
		-e K6_STAGE_2_TARGET=20 \
		-e K6_STAGE_3_TARGET=30 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability.js

load-50:
	docker run --rm --network host \
		$(K6_ENV) \
		-e K6_STAGE_1_TARGET=10 \
		-e K6_STAGE_2_TARGET=25 \
		-e K6_STAGE_3_TARGET=50 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability.js

load-100:
	docker run --rm --network host \
		$(K6_ENV) \
		-e K6_STAGE_1_TARGET=10 \
		-e K6_STAGE_2_TARGET=50 \
		-e K6_STAGE_3_TARGET=100 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability.js

load-min-interval:
	BASE_URL=$(BASE_URL) \
		APP_CONTAINER_NAME=$(APP_CONTAINER_NAME) \
	DB_CONTAINER_NAME=nopcommerce_mssql_server \
	INSTALL_DB_NAME=$(INSTALL_DB_NAME) \
	INSTALL_DB_USER=$(INSTALL_DB_USER) \
	INSTALL_DB_PASSWORD=$(INSTALL_DB_PASSWORD) \
	K6_IMAGE=$(K6_IMAGE) \
	K6_FIXED_VUS=1 \
	K6_FIXED_DURATION=90s \
	MIN_INTERVAL_VALUE=$(MIN_INTERVAL_VALUE) \
	RESET_INTERVAL_VALUE=$(RESET_INTERVAL_VALUE) \
		PAYMENT_METHOD=$(PAYMENT_METHOD) \
		THINK_TIME_SECONDS=0 \
		ADD_TO_CART_PATH=$(ADD_TO_CART_PATH) \
		CHECKOUT_COUNTRY_ID=$(CHECKOUT_COUNTRY_ID) \
		CHECKOUT_STATE_ID=$(CHECKOUT_STATE_ID) \
		K6_SCRIPTS_DIR="$(PWD)/$(LOADTEST_DIR)" \
		WORKDIR="$(PWD)" \
		bash ./scripts/run-min-interval-load.sh

load-min-interval-1000:
	$(MAKE) load-min-interval MIN_INTERVAL_VALUE=1000

load-min-subtotal:
	BASE_URL=$(BASE_URL) \
		APP_CONTAINER_NAME=$(APP_CONTAINER_NAME) \
		DB_CONTAINER_NAME=nopcommerce_mssql_server \
		INSTALL_DB_NAME=$(INSTALL_DB_NAME) \
		INSTALL_DB_USER=$(INSTALL_DB_USER) \
		INSTALL_DB_PASSWORD=$(INSTALL_DB_PASSWORD) \
		K6_IMAGE=$(K6_IMAGE) \
		K6_FIXED_VUS=1 \
		K6_FIXED_DURATION=3m \
		MIN_INTERVAL_VALUE=$(MIN_INTERVAL_VALUE) \
		RESET_INTERVAL_VALUE=$(RESET_INTERVAL_VALUE) \
		MIN_SUBTOTAL_VALUE=$(MIN_SUBTOTAL_VALUE) \
		RESET_SUBTOTAL_VALUE=$(RESET_SUBTOTAL_VALUE) \
		MIN_SUBTOTAL_INCLUDING_TAX=$(MIN_SUBTOTAL_INCLUDING_TAX) \
		RESET_SUBTOTAL_INCLUDING_TAX=$(RESET_SUBTOTAL_INCLUDING_TAX) \
		MIN_TOTAL_VALUE=$(MIN_TOTAL_VALUE) \
		RESET_TOTAL_VALUE=$(RESET_TOTAL_VALUE) \
		INTERVAL_FAILURE_PHASE_DURATION=$(INTERVAL_FAILURE_PHASE_DURATION) \
		SECOND_FAILURE_PHASE_DURATION=$(SECOND_FAILURE_PHASE_DURATION) \
		PAYMENT_METHOD=$(PAYMENT_METHOD) \
		THINK_TIME_SECONDS=2 \
		REALISTIC_ADD_TO_CART_PATH=$(REALISTIC_ADD_TO_CART_PATH) \
		FAILURE_ADD_TO_CART_PATH=$(FAILURE_ADD_TO_CART_PATH) \
		ADD_TO_CART_PATH=$(if $(strip $(ADD_TO_CART_PATH)),$(ADD_TO_CART_PATH),$(FAILURE_ADD_TO_CART_PATH)) \
		CHECKOUT_COUNTRY_ID=$(CHECKOUT_COUNTRY_ID) \
		CHECKOUT_STATE_ID=$(CHECKOUT_STATE_ID) \
		K6_SCRIPTS_DIR="$(PWD)/$(LOADTEST_DIR)" \
		WORKDIR="$(PWD)" \
		bash ./scripts/run-min-subtotal-load.sh

load-min-subtotal-1000:
	$(MAKE) load-min-subtotal MIN_SUBTOTAL_VALUE=1000 MIN_TOTAL_VALUE=1000

# Realistic user behavior: 20 VUs with a 3-second impatient confirm timeout
# Demonstrates a mixed population: most users wait normally, a minority abandon if confirm-order is slow
load-realistic:
	@echo "load-realistic product: $(REALISTIC_PRODUCT_NAME) ($(REALISTIC_ADD_TO_CART_PATH))"
	docker run --rm --network host \
		$(K6_ENV) \
		-e ADD_TO_CART_PATH=$(REALISTIC_ADD_TO_CART_PATH) \
		-e K6_STAGE_1_DURATION=30s \
		-e K6_STAGE_1_TARGET=10 \
		-e K6_STAGE_2_DURATION=2m \
		-e K6_STAGE_2_TARGET=15 \
		-e K6_STAGE_3_DURATION=3m \
		-e K6_STAGE_3_TARGET=15 \
		-e K6_STAGE_4_DURATION=30s \
		-e K6_STAGE_4_TARGET=0 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-realistic-abandonment.js

load-business-failure:
	@echo "load-business-failure product: $(FAILURE_PRODUCT_NAME) ($(FAILURE_ADD_TO_CART_PATH))"
	docker run --rm --network host \
		$(K6_ENV) \
		-e ADD_TO_CART_PATH=$(FAILURE_ADD_TO_CART_PATH) \
		-e K6_FIXED_VUS=1 \
		-e K6_FIXED_DURATION=3m \
		-e THINK_TIME_SECONDS=2 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-business-failure.js

# Loadtest mode: uses docker-compose.loadtest.yml with resource constraints
# This creates controlled degradation instead of instant crashes
up-loadtest:
	$(COMPOSE_LOADTEST) up -d --build

down-loadtest:
	$(COMPOSE_LOADTEST) down

# Controlled degradation profile - use AFTER up-loadtest
load-degrade:
	docker run --rm --network host \
		$(K6_ENV) \
		-e K6_STAGE_1_DURATION=30s \
		-e K6_STAGE_1_TARGET=15 \
		-e K6_STAGE_2_DURATION=2m \
		-e K6_STAGE_2_TARGET=30 \
		-e K6_STAGE_3_DURATION=2m \
		-e K6_STAGE_3_TARGET=40 \
		-e K6_STAGE_4_DURATION=30s \
		-e K6_STAGE_4_TARGET=0 \
		$(K6_SCRIPTS_MOUNT) \
		$(K6_IMAGE) run /scripts/checkout-observability.js

urls:
	@echo "Store:      $(BASE_URL)"
	@echo "Grafana:    http://localhost:3000"
	@echo "Prometheus: http://localhost:9090"
	@echo "Tempo API:  http://localhost:3200"
