using System.Diagnostics;
using Nop.Core.Events;
using Nop.Core.Infrastructure;
using Nop.Core.Observability;
using Nop.Services.Logging;

namespace Nop.Services.Events;

/// <summary>
/// Represents the event publisher implementation
/// </summary>
public partial class EventPublisher : IEventPublisher
{
    #region Methods

    protected static Activity StartPublishActivity<TEvent>()
    {
        var activity = NopTelemetry.ActivitySource.StartActivity("nop.event.publish", ActivityKind.Internal);
        activity?.SetTag("nop.event.type", typeof(TEvent).Name);
        activity?.SetTag("nop.stop_processing", false);
        return activity;
    }

    protected static Activity StartConsumeActivity<TEvent>(object consumer)
    {
        var activity = NopTelemetry.ActivitySource.StartActivity("nop.event.consume", ActivityKind.Internal);
        activity?.SetTag("nop.event.type", typeof(TEvent).Name);
        activity?.SetTag("nop.consumer.type", consumer.GetType().Name);
        activity?.SetTag("nop.stop_processing", false);
        return activity;
    }

    /// <summary>
    /// Publish event to consumers
    /// </summary>
    /// <typeparam name="TEvent">Type of event</typeparam>
    /// <param name="event">Event object</param>
    /// <returns>A task that represents the asynchronous operation</returns>
    public virtual async Task PublishAsync<TEvent>(TEvent @event)
    {
        //get all event consumers
        var consumers = EngineContext.Current.ResolveAll<IConsumer<TEvent>>().ToList();
        using var publishActivity = StartPublishActivity<TEvent>();

        foreach (var consumer in consumers)
        {
            using var consumeActivity = StartConsumeActivity<TEvent>(consumer);

            try
            {
                //try to handle published event
                await consumer.HandleEventAsync(@event);

                if (@event is IStopProcessingEvent { StopProcessing: true })
                {
                    publishActivity?.SetTag("nop.stop_processing", true);
                    consumeActivity?.SetTag("nop.stop_processing", true);
                    break;
                }
            }
            catch (Exception exception)
            {
                consumeActivity?.SetStatus(ActivityStatusCode.Error);
                consumeActivity?.AddEvent(new ActivityEvent("exception"));

                //log error, we put in to nested try-catch to prevent possible cyclic (if some error occurs)
                try
                {
                    var logger = EngineContext.Current.Resolve<ILogger>();
                    if (logger == null)
                        return;

                    await logger.ErrorAsync(exception.Message, exception);
                }
                catch
                {
                    // ignored
                }
            }
        }
    }

    #endregion
}
