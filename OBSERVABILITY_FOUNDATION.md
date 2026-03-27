# Step 2 Phase 1 Implementation Notes

## Goal

This document explains the first implementation pass for Step 2: adding a general OpenTelemetry tracing foundation to nopCommerce without committing yet to one specific assignment flow and without adding custom metrics yet.

The idea of this phase was to create a safe baseline:

- app-wide HTTP tracing
- one shared custom `ActivitySource`
- tracing at infrastructure boundaries only
- a local backend stack using OTLP, OpenTelemetry Collector, Tempo, and Grafana

This phase does **not** yet add flow-specific spans in controllers/services and does **not** add custom metrics.

## What Changed

### 1. OpenTelemetry was added to the web host

I added the required OpenTelemetry packages to the web project in `src/Presentation/Nop.Web/Nop.Web.csproj`.

Then I wired tracing into startup from `src/Presentation/Nop.Web/Program.cs` by calling:

```csharp
builder.Services.AddNopOpenTelemetry(builder.Environment);
```

Instead of putting all tracing configuration inline in `Program.cs`, I created a small helper file:

- `src/Presentation/Nop.Web/OpenTelemetryStartupExtensions.cs`

That helper configures:

- ASP.NET Core tracing
- `HttpClient` tracing
- the custom nopCommerce `ActivitySource`
- OTLP export when `OTEL_EXPORTER_OTLP_ENDPOINT` is present
- console export in development when OTLP is not configured

I also filtered out obvious static asset requests such as `.css`, `.js`, `.png`, `.svg`, `.woff`, etc. so trace output is less noisy.

### 2. A shared telemetry helper was introduced

I created:

- `src/Libraries/Nop.Core/Observability/NopTelemetry.cs`

This file contains:

- `ServiceName = "nopcommerce-web"`
- `ActivitySourceName = "NopCommerce.Observability"`
- one shared `ActivitySource`

This gives the project one central place to create custom spans in a consistent way.

### 3. Repository write operations were instrumented

I added tracing only to the write boundaries in:

- `src/Libraries/Nop.Data/EntityRepository.cs`

The following operations now create custom spans:

- `nop.repository.insert`
- `nop.repository.update`
- `nop.repository.delete`

The spans only include safe structural tags:

- `nop.entity.type`
- `nop.publish_event`

This was done for:

- single-entity insert/update/delete
- bulk insert/update/delete
- predicate delete

If one of these operations throws, the activity is marked as failed before the exception is rethrown.

The reason for choosing this boundary is that repository writes are centralized and already form a clean architecture seam.

### 4. Internal event publishing was instrumented

I added tracing to:

- `src/Libraries/Nop.Services/Events/EventPublisher.cs`

This now creates:

- one parent span: `nop.event.publish`
- one child span per consumer: `nop.event.consume`

The tags are intentionally limited to:

- `nop.event.type`
- `nop.consumer.type`
- `nop.stop_processing`

If a consumer throws, the consumer span is marked with error status and an exception event is recorded before the existing logger behavior continues.

I kept the current nopCommerce event behavior the same:

- consumers are still processed sequentially
- stop-processing behavior still works
- exceptions are still caught and logged so dispatch can continue

### 5. A local observability stack was added

I kept the original `docker-compose.yml` focused on the app and database.

Then I added a separate overlay:

- `docker-compose.observability.yml`

This overlay adds:

- OpenTelemetry Collector
- Tempo
- Grafana

Supporting config files were also added:

- `assessment/observability/otel-collector/config.yaml`
- `assessment/observability/tempo/tempo.yml`
- `assessment/observability/grafana/provisioning/datasources/tempo.yml`

The intended flow is:

```text
nopCommerce -> OTLP -> OpenTelemetry Collector -> Tempo -> Grafana
```

The app container gets:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
```

Grafana is pre-provisioned with Tempo as the default trace datasource.

## Runtime Fixes I Had To Make

While validating the stack, two configuration problems appeared:

1. Tempo could not write to its local storage volume because of permissions.
   I fixed this in the compose overlay by running the Tempo container as root.

2. The collector was initially binding OTLP receivers to loopback only.
   I changed the collector config to bind to `0.0.0.0:4317` and `0.0.0.0:4318` so the app container could actually export to it.

I also corrected the exporter type in the collector config to use `otlp_grpc`.

## How To Run It

Use:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
```

Useful endpoints:

- App: `http://localhost`
- Grafana: `http://localhost:3000`
- Tempo HTTP API: `http://localhost:3200`

Grafana default login:

- username: `admin`
- password: `admin`

To stop everything:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml down
```
