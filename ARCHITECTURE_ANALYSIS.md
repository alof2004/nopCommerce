# Architecture Analysis

I have spent time analyzing the nopCommerce architecture to understand how its layering, event handling, and composition patterns affect where and how to add OpenTelemetry instrumentation. Following the assignment hint, I started with `Nop.Services` and `Nop.Core` first.

## 1) Core + Services Focus (Primary Reading)

### Nop.Core

First, I started with `Nop.Core` because it is the foundational layer that the rest of the solution depends on. By reading its folders and files, I confirmed that it contains the base contracts, shared models, and cross-cutting primitives used throughout nopCommerce. For example, the `Domain` folder provides business entities, enums, and domain events used across multiple modules, while the `Events` folder defines shared event contracts such as `IEventPublisher`.

Other `Nop.Core` folders I looked at were:

- `Infrastructure`: application engine and startup abstractions (`NopEngine`, `INopStartup`, type discovery).
- `Configuration`: app-wide configuration contracts and settings models (`AppSettings`, `IConfig`, `ISettings`).
- `Caching`: shared cache contracts and implementations used by upper layers.
- `Http` and `Security`: shared HTTP defaults, route/cookie constants, and security-related defaults.

### Nop.Services

After that, I looked at `Nop.Services` and quickly realized that it is organized with a clear domain structure, meaning each folder maps to a business area (`Orders`, `Customers`, `Catalog`, and so on) and groups services, managers, and event consumers for that area.

For example, the `Orders` folder contains core workflow orchestration such as `OrderProcessingService` and `ShoppingCartService`, where checkout, payment flow, stock updates, and order status transitions are coordinated (`src/Libraries/Nop.Services/Orders/OrderProcessingService.cs`, `src/Libraries/Nop.Services/Orders/ShoppingCartService.cs`).

This structure made the architecture easier to understand since business behavior is concentrated in `Nop.Services`, while more general concepts stay in `Nop.Core`. From an observability perspective, this is useful because service-layer operations are where the observability value is highest.

### Layer Organization and Dependency Rules

| Layer | Responsibilities | Depends On | Evidence |
| --- | --- | --- | --- |
| `Nop.Core` | Domain abstractions, infrastructure contracts, shared primitives (events, base entities, engine contracts) | No project dependency on other nop layers | `src/Libraries/Nop.Core/Nop.Core.csproj`, `src/Libraries/Nop.Core/Events/IEventPublisher.cs`, `src/Libraries/Nop.Core/Infrastructure/INopStartup.cs` |
| `Nop.Services` | Business logic, plugin managers, application services, event consumers/producers | `Nop.Core`, `Nop.Data` | `src/Libraries/Nop.Services/Nop.Services.csproj`, `src/Libraries/Nop.Services/Orders/OrderProcessingService.cs`, `src/Libraries/Nop.Services/Events/EventPublisher.cs` |
| `Nop.Data` | DB provider abstraction, linq2db access, repository implementation, migrations | `Nop.Core` | `src/Libraries/Nop.Data/Nop.Data.csproj`, `src/Libraries/Nop.Data/INopDataProvider.cs`, `src/Libraries/Nop.Data/NopDbStartup.cs` |
| `Nop.Web.Framework` | Web infrastructure, DI registration, middleware startup units, MVC wiring | `Nop.Core`, `Nop.Data`, `Nop.Services` | `src/Presentation/Nop.Web.Framework/Nop.Web.Framework.csproj`, `src/Presentation/Nop.Web.Framework/Infrastructure/NopStartup.cs`, `src/Presentation/Nop.Web.Framework/Infrastructure/*Startup.cs` |
| `Nop.Web` | App host, controllers, factories, public/admin presentation | `Nop.Core`, `Nop.Data`, `Nop.Services`, `Nop.Web.Framework` | `src/Presentation/Nop.Web/Nop.Web.csproj`, `src/Presentation/Nop.Web/Program.cs`, `src/Presentation/Nop.Web/Controllers/CheckoutController.cs` |
| Plugins (runtime extension) | Optional feature modules extending routes, events, services | Runtime-loaded into web host; often depend on Services/Core | `src/Presentation/Nop.Web.Framework/Infrastructure/Extensions/ApplicationPartManagerExtensions.cs`, `src/Libraries/Nop.Core/Infrastructure/WebAppTypeFinder.cs` |

Dependency rules implied by this structure:

1. `Nop.Core` is the base layer; upper layers should not push business-specific concepts and shouldn't depend on other nop layers.
2. `Nop.Data` encapsulates persistence and should not depend on service/business implementations.
3. `Nop.Services` owns business workflows and orchestrates repository, events, and plugins.
4. Presentation (`Nop.Web`, `Nop.Web.Framework`) composes services and middleware; it is not the place for deep business policy.
5. Runtime startup is not hardcoded in one place; `NopEngine` discovers all `INopStartup` implementations and executes them ordered by `Order` (`src/Libraries/Nop.Core/Infrastructure/NopEngine.cs`).

## 2) Internal Event Handling: IEventPublisher

First, I opened `IEventPublisher` to check the contract.
The interface itself is simple:

```csharp
public partial interface IEventPublisher
{
    Task PublishAsync<TEvent>(TEvent @event);
}
```

After that, I used global search in VS Code (`Ctrl+Shift+F`) for `IEventPublisher` to find the implementation and all usage points.

The key functions I found are:

1. `PublishAsync<TEvent>(TEvent @event)` in `IEventPublisher` / `EventPublisher`  
   This is the main "send event" method. When something happens this method finds every consumer that listens to that event type and calls them one by one. It waits for each handler before moving to the next, can stop early if the event asks to stop (`IStopProcessingEvent`), and if one handler fails it logs the error and continues with the remaining handlers.
2. `EntityInsertedAsync<T>(T entity)` in `EventPublisherExtensions`  
   This is a shortcut used after creating a database record. Instead of manually creating an event object every time, the code calls this method and it automatically publishes `EntityInsertedEvent<T>` for that entity.
3. `EntityUpdatedAsync<T>(T entity)` in `EventPublisherExtensions`  
   Same helper pattern but for updates. After an entity changes, this helper publishes `EntityUpdatedEvent<T>` so any interested part of the system can react.
4. `EntityDeletedAsync<T>(T entity)` in `EventPublisherExtensions`  
   Same helper pattern but for deletes. When an entity is removed, it publishes `EntityDeletedEvent<T>` so cleanup logic (cache invalidation, follow-up actions, etc.) can run.

The file is registered in `src/Presentation/Nop.Web.Framework/Infrastructure/NopStartup.cs` as a singleton with `services.AddSingleton<IEventPublisher, EventPublisher>();`.

I tried to find a real flow example, starting from the web layer. In the standard checkout flow, the request enters `CheckoutController.ConfirmOrder`, which calls `PlaceOrderAsync`:

```csharp
// src/Presentation/Nop.Web/Controllers/CheckoutController.cs
var placeOrderResult = await _orderProcessingService.PlaceOrderAsync(processPaymentRequest);
```

From there, `OrderProcessingService` builds and saves the order in `SaveOrderDetailsAsync`, and that method calls:

```csharp
// src/Libraries/Nop.Services/Orders/OrderProcessingService.cs
await _orderService.InsertOrderAsync(order);
```

`OrderService` then writes through the repository:

```csharp
// src/Libraries/Nop.Services/Orders/OrderService.cs
await _orderRepository.InsertAsync(order);
```

At repository level, the entity is inserted and `IEventPublisher` is used immediately after persistence:

```csharp
// src/Libraries/Nop.Data/EntityRepository.cs
await _dataProvider.InsertEntityAsync(entity);
if (publishEvent)
    await _eventPublisher.EntityInsertedAsync(entity);
```

That helper creates `EntityInsertedEvent<Order>` and sends it through `PublishAsync`. A concrete order consumer is `ModelCacheEventConsumer`, which invalidates order-related caches:

```csharp
// src/Presentation/Nop.Web/Infrastructure/Cache/ModelCacheEventConsumer.cs
public virtual async Task HandleEventAsync(EntityInsertedEvent<Order> eventMessage)
{
    await _staticCacheManager.RemoveByPrefixAsync(NopModelCacheDefaults.HomepageBestsellersIdsPrefixCacheKey);
    await _staticCacheManager.RemoveByPrefixAsync(NopModelCacheDefaults.ProductsAlsoPurchasedIdsPrefixCacheKey);
}
```

The same order flow also publishes a business event later in `PlaceOrderAsync`:

```csharp
// src/Libraries/Nop.Services/Orders/OrderProcessingService.cs
await _eventPublisher.PublishAsync(new OrderPlacedEvent(order));
```

So in one real request, `IEventPublisher` is used at two levels:
1. Repository level (`EntityInsertedEvent<Order>`) for generic entity lifecycle reactions.
2. Service/business level (`OrderPlacedEvent`) for order-domain reactions.

This is why it is a strong observability boundary: one central dispatcher captures multiple side effects without putting cross-cutting code directly inside the controller.
