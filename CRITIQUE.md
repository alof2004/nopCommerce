# Critique

## Student

|  |  |
| --- | --- |
| Name | Afonso Ferreira |
| NMEC | 113480  |
|  |    |

## What Helped and What Didn't

Honestly, nopCommerce was way more readable than I expected once I actually sat down with `Nop.Services` and `Nop.Core` for a while. After the initial "what is all this" phase, I could see where checkout actually happened, where stuff got saved to the database, and where events got fired off. That made it way easier to figure out where to add tracing without having to touch like every single class.

The three spots that saved me were `IOrderProcessingService`, `EntityRepository`, and `IEventPublisher`. These ended up being perfect places to instrument because they're already natural boundaries in the code. The HTTP request comes in through `CheckoutController`, the actual order placement logic happens in the order processing service, database writes go through the repository, and events get published through the event publisher. I didn't have to guess where things were happening - the architecture kind of told me where to look.

The annoying part though is that checkout isn't just one clean function call. It's spread across controllers, services, plugins, and a bunch of AJAX endpoints for the one-page checkout flow. So yeah, the code is layered, but the actual checkout flow at runtime bounces around between all these different pieces. That's why writing the load test was such a pain - I couldn't just hit one endpoint and call it a day. I had to deal with anti-forgery tokens, cart state, billing forms, shipping forms, payment method selection, payment info, and then finally the confirmation. It makes sense why it's like that (checkout IS a multi-step process), but it made finding good instrumentation points harder. I couldn't just trace one method and be done. I had to actually follow the flow through multiple controller actions and service calls to figure out what would give useful information vs just noise.

The plugin system made things less predictable too. `IEventPublisher` ended up being a great place to add tracing, but all the event consumers get discovered at runtime, so you can't just look at the code and know what's going to happen. The same thing happens with payment plugins as the checkout flow isn't all in one place, it's spread across the core system and whatever plugins are installed.

One smaller thing that caused some confusion: some settings exist in the backend but the admin UI doesn't really expose them in a user-friendly way. During testing, this meant I sometimes had to edit configuration files directly or even update the database with SQL to trigger certain failure scenarios. That's not really a tracing problem, but it made testing specific failure cases way more manual than it should've been.

The load tests also taught me that application design and actual deployment limits are different things. When I pushed enough concurrent checkout traffic through the local Docker setup, the web container just died from running out of memory instead of gracefully handling failures. That doesn't mean nopCommerce can't scale - it means my local setup with instrumentation and everything hit a wall. From an observability perspective, that's a problem because once the process is dead, all the nice telemetry is gone too. At that point I'm just looking at Docker logs and trying to figure out what happened.

## What I'd Change If I Kept Going

If I had to keep working on this, I'd definitely try to keep observability stuff in the infrastructure layer and not let it bleed into all the business logic.

The decorator pattern I used for `IOrderProcessingService` worked really well. It gave me one clean root span for the whole checkout flow without having to mess with the actual service code too much. I'd probably use that same approach for other important flows instead of trying to instrument inside big service classes. The tradeoff is you end up with more wrapper classes and more DI registrations to manage, but the business logic stays way cleaner.

I'd also keep the split between `NopTelemetry` and `CheckoutTelemetry`, but not just because it keeps things tidier. The real benefit is separation of responsibility. `NopTelemetry` holds the shared observability primitives used across the application, while `CheckoutTelemetry` defines the checkout-specific vocabulary: metric names, tags, and helper methods that only make sense for that flow. That keeps the generic telemetry layer from getting coupled to one feature and makes it much easier to extend observability later for something like catalog or search without polluting the shared infrastructure with checkout-specific concepts.

The configuration thing is something I'd definitely want to fix. Like I mentioned before, some settings are kind of hidden and hard to change through the normal admin UI. During this assignment I had to edit config files or even write SQL to trigger certain failures. That's fine for a school project but in a real system, if operators can't easily reproduce failure scenarios, they can't really validate if the observability is working. You'd need to add proper UI for these settings, which is more work, but it would make the system way more testable.

The logging side is... okay. I added basic correlation between traces and logs so you can go from an error in the logs to the actual trace, which helps. But I wouldn't say logging is as mature as the traces and metrics. It's better than nothing, but there's room for improvement.

Oh, and one thing I learned the hard way: not every metric that sounds good in theory is actually useful. I originally added a metric for in-flight checkouts because I thought it would be a good early warning signal for pressure on the system. Turns out it was pretty useless in practice - most of the time it just showed zero because checkout is fast and Prometheus scrapes at intervals. It didn't tell a clear story so I got rid of it. Good reminder that metrics are only valuable if they actually help you understand what's happening.

## How the Metrics Evolved

One of the bigger changes I made was replacing the simple failure counter with `nop.checkout.stage_completions_total`. This was actually a pretty significant improvement.

The original failure counter was super basic - it just told me "checkout is failing" but that's about it. It was totally reactive. By the time I saw failures in the metric, users were already having problems.

The stage completions metric is way better because it tracks both successes AND failures for each checkout stage. That means I can actually calculate success rates per stage and catch problems earlier. Like, I can see the payment stage starting to slip from 100% to 99% to 98% before the whole checkout flow looks completely broken. That's a way better early warning signal.

It also gives way more context. Instead of just "checkout is broken," I can see stuff like "payment stage is at 97% success but persist_order is still at 100%." That tells me way more about where to look. If I see failures concentrated in one specific stage, that immediately narrows down what to investigate.

I think this fits what the assignment was asking for - metrics that are actually operationally useful, not just numbers. A metric that only tells you things are already on fire is okay I guess, but a metric that shows things starting to degrade while you can still do something about it is way better.

The funny thing is this wasn't even that hard to change. The code was already incrementing counters, I just had to think about what shape would give better information. Good reminder that how you design metrics matters more than just collecting a ton of data.

## Dashboard Changes

The dashboard went through a bunch of iterations once I actually started using it with real traffic. Some stuff that looked good on paper turned out to be not that useful in practice.

The biggest change was cutting panels that didn't actually help. The inflight checkout panel is the best example - it was technically correct, but it just sat at zero most of the time because checkouts are fast and Prometheus only scrapes every so often. Replacing that with median checkout time made the dashboard way more useful.

Another thing I changed was using rates instead of totals where it made sense. Like, showing "total successful checkouts in the selected time range" is kind of useless because the number changes meaning depending on how big your time window is. Showing checkouts per second is way easier to understand and actually tells you if throughput is dropping.

I also made the stage success rate panel way more prominent. That one ended up being super important because it gives you early warning before the overall error rate looks really bad. It's definitely one of the first things I'd check if something was going wrong.

The way I organized the dashboard follows how I'd actually debug a problem:

- First, is something broken right now?
- Which part of checkout is having issues?
- What failures are happening and when did they start?
- Finally, let me look at some actual traces

I kept the stage filter because it was actually useful when I wanted to focus on one part of the checkout flow without rewriting queries. I ended up removing the interval filter though. It sounded flexible in theory, but in practice it just added noise to the dashboard. Fixing the Prometheus window to a sensible default made the panels easier to read and made the whole dashboard feel more stable during demos and testing.

Main takeaway: dashboards shouldn't just be technically correct, they should actually help you make decisions. If a panel doesn't help answer "what's wrong?" or "what should I check next?", it probably doesn't need to be there.

## The Most Important Change

The biggest single change I made was probably the decorator around `IOrderProcessingService` to create that root checkout span. The built-in ASP.NET Core instrumentation could show me the HTTP request and some database activity, but it couldn't really show the business concept that matters: "placing an order."

I thought about putting that span in the controller, but that felt too tied to the web layer. And pushing observability logic deep into the service code would've been way too invasive. The decorator was the sweet spot - it sits at a natural boundary and doesn't mess with the actual service interface.

I did have to add some instrumentation directly inside `OrderProcessingService` though. That was kind of a compromise. The internal checkout stages (prepare, payment, persist, move items, finalize) don't have cleaner boundaries I could hook into, so if I wanted visibility into each stage I had to instrument from inside the service. I kept it pretty coarse on purpose though - I tracked the major stages instead of trying to trace every single helper method. That gave enough structure to be useful without turning the whole service into tracing code.

The privacy stuff was another place where I tried to be surgical about it. Instead of trying to remember at every single call site which fields were safe to export, I just added one central sanitizing processor that runs before anything gets sent to the collector. That's the kind of rule that should live in one place - way easier to maintain and way less error-prone.

Overall, I think nopCommerce was actually pretty instrumentable without having to redesign everything, mostly because the service layer, repository, and event publisher are already good boundaries. But this assignment also showed me that "layered architecture" doesn't automatically mean "observability-ready." Checkout still spreads across controllers, services, plugins, and config. The reason my changes worked is because I kept them small and put them at boundaries that already existed and made sense.
