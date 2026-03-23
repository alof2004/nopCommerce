# Critique

## Student

|  |  |
| --- | --- |
| Name | Afonso Ferreira |
| NMEC | 113480  |
|  |    |

## What Helped and What Hindered

What helped me most was that nopCommerce is layered in a way that is actually readable once I spent some time in `Nop.Services` and `Nop.Core`. I could see fairly quickly where the checkout logic was orchestrated, where data writes happened, and where side effects were fanned out. That gave me a few strong places to instrument without touching every class involved in checkout.

The three most useful seams were `IOrderProcessingService`, `EntityRepository`, and `IEventPublisher`. Those boundaries are basically the reason the final trace makes sense. The request starts in `CheckoutController`, the main backend work is rooted at the order-processing service boundary, repository writes stay visible, and event publishing still shows up in the trace without me having to instrument every single consumer.

What made the work harder is that checkout is not one clean service call. In practice it is spread across controllers, service code, plugins, and one-page checkout AJAX endpoints. So even though the architecture is layered, the real runtime behavior still cuts across several parts of the system. That is why the load test had to do much more than call one endpoint. It had to deal with anti-forgery tokens, cart state, billing, shipping, payment selection, payment info, and final confirmation, which makes sense since the checkout flow is built as a sequence of dependent steps rather than one isolated backend operation. Because of that, it was also harder to find the best instrumentation points at first. I could not just trace one method and be done with it. I had to follow how state moved between controller actions, service calls, and plugin logic before I could decide where tracing would actually be meaningful instead of just noisy.

The plugin and event model also made observability less predictable. `IEventPublisher` is a very good instrumentation boundary, but its consumers are discovered dynamically, so the full behavior is not obvious just from reading the code. Payment plugins create the same kind of problem. The checkout flow is not fully contained in one service or one assembly, which is good for extensibility but harder for observability.

Another smaller issue I noticed was configuration visibility. Some settings exist in the backend but are not exposed in a very friendly way in the admin UI. During testing, that meant some failure modes were easier to trigger through direct configuration changes or SQL than through the normal administration surface. That is not a tracing problem by itself, but it matters because it makes controlled failure testing less repeatable.

The load tests also showed me the difference between application design and deployment limits. With enough concurrent checkout traffic in the local Docker setup, the web container eventually died from memory pressure instead of continuing to emit clean classified failures. That does not mean nopCommerce cannot scale. It means this specific instrumented local setup hits a hard resource limit quickly. From an observability point of view, that matters because once the process is dead, the nice in-process telemetry is gone too. At that point I had to look at container state and logs, not just traces and metrics.

## What I Would Change Going Forward, and the Cost

If I were continuing this work, I would keep observability as an infrastructure concern instead of letting it leak into random business services.

The decorator around `IOrderProcessingService` worked well because it gave me one clean root span for checkout. I would keep that pattern for other important workflows instead of making observability depend on knowledge of one big service class. The cost is moderate: more wrappers, more DI registrations, and a bit more testing. The benefit is that the business logic stays cleaner.

I would also keep the split between shared telemetry primitives and feature-specific telemetry policy. Having a general `NopTelemetry` plus a more focused `CheckoutTelemetry` is much better than trying to dump every tag and metric name into one shared helper. If observability later expands into search, catalog, pricing, or admin flows, each area should have its own small telemetry module. The cost is mostly organization. The benefit is that the observability code does not turn into a giant global bucket of constants.

I would also make operational settings and failure-injection paths easier to control from supported configuration surfaces. During this assignment I sometimes had to work around how configuration is exposed just to reproduce certain behaviors. In a real system, that becomes an operational problem. If operators cannot easily reproduce a failure mode, it is much harder to validate whether the telemetry is actually useful. The cost there is extra UI and mapping work, but the result is a system that is easier to test and operate.

I also think the logging story matters. I added basic trace-log correlation, which makes it easier to move from an error log to the trace that produced it. That said, I still would not call the logging side fully mature. It is better than before, but traces and metrics are still the stronger part of this implementation.

One good lesson from the metric work is that not every metric that sounds good on paper is actually good in practice. I originally added an inflight checkout metric because it seemed like a useful early pressure signal. In reality, it was too narrow and too dependent on scrape timing to be helpful in this setup. Most of the time it showed zero and did not tell a clear story. I removed it and kept the metrics that were easier to interpret under load. That was a good reminder that a metric is only valuable if someone can look at it and know what it means.

## Metric Design Evolution

One of the biggest improvements I made during the implementation was moving away from a simple failure counter and toward `nop.checkout.stage_completions_total`.

The original failure counter could tell me that checkout was failing, but not much more than that. It was reactive. I would only see the problem after it was already affecting users.

The stage completions metric is much more useful because it tracks both success and failure for each stage. That makes it possible to calculate stage success rate and spot degradation earlier. For example, I can see the payment stage slipping before the overall flow looks completely broken. That is a much better signal for an operator.

It also gives much better context. Instead of just seeing "checkout is failing," I can see that payment is degrading while persist order is still healthy, or that failures are mostly concentrated in a later stage. That narrows down the next place to investigate much faster.

I think this change fits the assignment well because the brief explicitly asks for metrics that are operationally useful. A metric that only tells me the system is already broken is fine, but a metric that shows degradation while there is still time to react is better.

The cost of this change was small. The system was already incrementing counters; the real difference was choosing a metric shape that gave better information. That was a useful reminder that metric design matters more than just collecting more numbers.

## Dashboard Organization and Iteration

The dashboard changed quite a bit once I started using it with real traffic. A few things looked fine in theory and then turned out not to be very helpful in practice.

The first big change was removing panels that did not really help tell the story. The best example was the inflight checkout panel. It was technically valid, but in this environment it sat at zero most of the time because checkout requests were fast and Prometheus scraped at intervals. Replacing it with median checkout time made the dashboard much easier to read.

Another improvement was moving from totals to rates where that made more sense. A total over the selected time range can be misleading because it changes meaning depending on the dashboard window. A rate is easier to compare at a glance and gives a better sense of whether throughput is dropping right now.

I also made stage success rate much more visible. That panel ended up being important because it gives early warning before the top-level error rate becomes obviously bad. It is one of the panels I would look at first during an incident.

The final layout follows the way I would actually investigate a problem:

- first, detect whether something is wrong now
- then see which part of checkout is degrading
- then look at failures and trends
- finally open traces for detail

That structure made the dashboard feel less like a collection of graphs and more like a workflow.

I also kept template variables for stage and interval so I could narrow the view without editing queries. That made the dashboard much more practical during testing.

The main lesson for me here was that a dashboard should not just be technically correct. It should help someone make a decision. If a panel does not help answer "what is wrong?" or "what should I look at next?", it probably does not deserve space on the screen.

## The Surgical Change

The most important surgical change I made was the decorator around `IOrderProcessingService` to create the root checkout span. I needed that because the built-in instrumentation could show the HTTP request and some downstream activity, but it could not express the business-level unit that actually matters: placing an order.

Putting that root span in the controller would have made the tracing too tied to the presentation layer. Pushing exporter-specific logic deep into service code would have been too invasive. The decorator was the cleanest middle ground because it sat at a good boundary and kept the service contract intact.

I still had to add some instrumentation inside `OrderProcessingService` itself. That was the second compromise. The internal checkout stages do not have cleaner external seams right now, so if I wanted stage-level visibility I had to instrument inside the service. I kept that coarse on purpose. I tracked stages like prepare, payment, persist order, move items, and finalize instead of trying to trace every helper method. That gave useful structure without turning the service into tracing code.

The privacy work was another intentional surgical choice. Instead of trying to remember at every call site which fields were safe, I added a central sanitizing processor before export. That is the kind of rule that should live in one place. It is easier to maintain and much less error-prone.

Overall, I think nopCommerce was instrumentable without a large redesign because the service layer, repository boundary, and event publisher are all strong seams. At the same time, this assignment made it clear to me that "layered" does not automatically mean "observability-ready." Checkout still spreads across controllers, services, plugins, and runtime configuration. The reason my changes worked is that I kept them small and placed them at boundaries that were already meaningful.
