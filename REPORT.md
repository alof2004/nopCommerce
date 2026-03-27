# Observability Report

## Goal

The goal of this work was to add observability to nopCommerce for the checkout flow without forcing a large architectural rewrite. The focus was the backend order-placement path, where the most important business work happens after the customer confirms the order.

## Main Architectural Decisions

### 1. Use boundary-based instrumentation

Instead of adding spans in many small methods, observability was added at the main architectural seams:

- HTTP entry in `CheckoutController`
- service boundary around `IOrderProcessingService`
- orchestration stages inside `OrderProcessingService`
- repository writes in `EntityRepository`
- internal event fan-out in `EventPublisher`

This was the main design choice because nopCommerce already has clear layering. Instrumenting boundaries gives broad visibility with much lower coupling than scattering telemetry code across business services.

### 2. Keep observability infrastructure separate from business logic

Telemetry registration stays in startup and infrastructure code, while business code only contains the minimum spans and metrics needed to describe the checkout flow. A decorator around `IOrderProcessingService` was used to create the root span `nop.checkout.place_order` without pushing more cross-cutting logic into controllers or changing the service contract.

### 3. Split shared telemetry from flow-specific telemetry

The telemetry layer was split into:

- `NopTelemetry` for shared observability primitives
- `CheckoutTelemetry` for checkout-specific metric names, tags, and helper methods

This keeps the base telemetry layer reusable and avoids turning one helper into a catch-all class. It also makes it easier to extend observability later to catalog, customer, or shipping flows.

### 4. Prefer privacy controls at one central point

Sensitive data was intentionally excluded from exported telemetry. A sanitizing processor removes risky tags such as raw URLs with query strings, address-like values, payment-related fields, XML payloads, IP-like tags, and raw exception details.

This was important because checkout objects contain customer and payment information, so privacy could not depend on each individual call site remembering what is safe to export.

### 5. Build on the existing architecture instead of rewriting it

nopCommerce already has useful seams for observability:

- centralized startup
- a shared repository layer
- a single event publisher
- a layered services architecture

Because of that, the implementation stayed incremental. The project gained observability without redesigning checkout, data access, or plugin handling.

## Important Technical Choices

- OpenTelemetry was wired once at the application composition root.
- The local stack exports traces and metrics through OTLP to an OpenTelemetry Collector.
- Tempo was used for traces, Prometheus for metrics, and Grafana for dashboards.
- Repository spans were limited to write operations because they are centralized and operationally important during checkout.
- Event publishing was instrumented with a parent publish span and child consumer spans to expose fan-out and plugin behavior.
- Checkout stages were kept coarse: `prepare`, `payment`, `persist_order`, `move_items`, and `finalize`.

## How The Design Evolved

The commit history shows a gradual evolution instead of one large change:

- `b9ab856a5d` introduced the initial OpenTelemetry foundation.
- `c44d58a43e` added Prometheus integration and a central processor for PII sanitization.
- `5446ba172e` made telemetry more general by separating `CheckoutTelemetry` from shared telemetry concerns.
- `d6e2317b09` improved stage-level checkout tracking.
- `5b302058f2` enhanced stage metrics and telemetry labeling.
- later dashboard commits refined the panels so they told a clearer operational story instead of just showing raw numbers.

This evolution matters because it shows the design was validated in practice and adjusted when a metric or panel was not useful enough.

## Metric Design Decisions

The most important metric decision was moving away from a simple failure-only counter toward `nop.checkout.stage_completions_total`.

That change made the dashboard more useful because it allows:

- success and failure tracking in the same metric
- stage-level success-rate analysis
- better failure attribution through `reason_code` and `subsystem`
- earlier detection of degradation before the whole flow looks broken

The stage duration histogram and end-to-end completion histogram were kept because together they answer two different questions:

- which internal stage is slow
- how long the whole backend checkout operation takes

## Limitations And Tradeoffs

- Checkout is spread across controllers, services, plugins, and AJAX endpoints, so there is no single perfect instrumentation point.
- Some stage spans had to be added inside `OrderProcessingService` because no cleaner external seam existed for those internal steps.
- Dynamic plugin loading and runtime event-consumer discovery make behavior harder to predict statically.
- Local load testing showed that infrastructure limits can still hide the application once the process dies; at that point telemetry disappears and Docker logs become necessary.

## Conclusion

The observability design follows the existing nopCommerce architecture instead of fighting it. The main decisions were to instrument boundaries, keep telemetry modular, centralize privacy protection, and prefer operationally useful metrics over noisy ones. That produced a solution that is easier to explain, safer to run, and easier to extend later.
