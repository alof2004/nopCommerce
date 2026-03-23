# Critique

## Student

| Field | Value |
| --- | --- |
| Name |  |
| Student Number |  |

## What Helped and What Hindered

One of the main things that helped the instrumentation was having the business logic is layered. By starting looking at `Nop.Services` and `Nop.Core` first helped me understand the flow way easily than if the application had a less clear layering. `Nop.Services` contains most of the business orchestration, `Nop.Data` gives a central repository boundary, and `IEventPublisher` provides a single internal fan-out point for side effects. That meant I could get meaningful coverage without scattering tracing code through every feature. In practice, three seams were especially helpful:

- `IOrderProcessingService` as the business boundary for the checkout flow
- `EntityRepository` as the persistence-adjacent boundary
- `IEventPublisher` as the event boundary

Those seams are the reason the final trace is coherent. The HTTP request enters through `CheckoutController`, the main backend flow is rooted at the order-processing service boundary, repository writes remain visible, and event publishing still appears in the trace without instrumenting each individual consumer.

The codebase also hindered the work in ways that matter architecturally. The checkout flow is not a simple service call. It is split across controller logic, service orchestration, plugin behavior, and one-page checkout AJAX endpoints. That made the runtime behavior harder to observe than the layering diagram suggests. The system is layered, but the checkout experience is still operationally cross-cutting. That is why the load test had to model anti-forgery tokens, cart handoff, billing, shipping, payment selection, payment info, and final confirmation rather than just calling one endpoint.

The plugin and event model also makes observability less predictable. `IEventPublisher` is a good boundary, but its consumers are discovered dynamically. That is good for extensibility and weaker for static reasoning. Similarly, payment behavior is partly defined by plugins, which means “the checkout flow” is not fully self-contained in one module.

One smaller but revealing issue was configuration visibility. Some settings that exist in the backend are not surfaced usefully in the admin UI. During testing, that meant some failure modes were easier to trigger through direct configuration changes or SQL than through the administration surface. That is not a tracing problem by itself, but it affects observability work because it makes controlled failure injection less reproducible for operators and testers.

The load tests also exposed an important distinction between application design and deployment shape. Under higher concurrent checkout load in the local Docker environment, the web container eventually terminated with an out-of-memory failure instead of continuing to produce classified checkout errors. That does not mean nopCommerce as a platform cannot support larger stores; it means this single-node, instrumented local setup reaches a hard resource boundary quickly. From an observability perspective, that mattered because once the process died, traces and custom metrics stopped being emitted. In other words, the dashboard could explain degradation while the app was alive, but total process death had to be understood through container state and logs rather than through graceful in-process telemetry. A practical way to improve this going forward would be to treat the deployment as a first-class architectural concern: set explicit memory budgets, isolate observability services from the storefront where possible, add health and availability telemetry alongside flow telemetry, and validate the application under a more production-like topology instead of a single overloaded developer host.

