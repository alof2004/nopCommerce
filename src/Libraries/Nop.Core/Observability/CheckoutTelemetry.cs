using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace Nop.Core.Observability;

/// <summary>
/// Checkout-specific span tags, metric names, and helper methods.
/// </summary>
public static class CheckoutTelemetry
{
    public const string ModeTag = "checkout.mode";
    public const string ResultTag = "checkout.result";
    public const string StageTag = "checkout.stage";
    public const string FailureReasonTag = "failure.reason_code";

    public const string ModeStandard = "standard";
    public const string ModeOpc = "opc";
    public const string ResultSuccess = "success";
    public const string ResultFailure = "failure";

    // Subsystem identifiers for granular failure tracking
    public const string SubsystemBasket = "basket";
    public const string SubsystemInventory = "inventory";
    public const string SubsystemPaymentProvider = "payment_provider";
    public const string SubsystemOrderProcessing = "order_processing";
    public const string SubsystemGeneral = "general";

    private static readonly Counter<long> AttemptsCounter =
        NopTelemetry.Meter.CreateCounter<long>("nop.checkout.attempts_total");

    private static readonly Counter<long> StageCompletionsCounter =
        NopTelemetry.Meter.CreateCounter<long>("nop.checkout.stage_completions_total");

    private static readonly Histogram<double> StageDurationHistogram =
        NopTelemetry.Meter.CreateHistogram<double>("nop.checkout.stage_duration_ms", "ms");

    private static readonly UpDownCounter<long> InflightRequestsCounter =
        NopTelemetry.Meter.CreateUpDownCounter<long>("nop.checkout.inflight_requests");

    public static string GetMode()
    {
        return Activity.Current?.GetBaggageItem(ModeTag) ?? ModeStandard;
    }

    public static void SetMode(string checkoutMode)
    {
        Activity.Current?.SetBaggage(ModeTag, NormalizeMode(checkoutMode));
    }

    public static Activity StartActivity(string name, string checkoutMode, string stage)
    {
        var activity = NopTelemetry.ActivitySource.StartActivity(name, ActivityKind.Internal);

        SetModeTag(activity, checkoutMode);
        activity?.SetTag(StageTag, stage);

        return activity;
    }

    public static void SetModeTag(Activity activity, string checkoutMode)
    {
        activity?.SetTag(ModeTag, NormalizeMode(checkoutMode));
    }

    public static void SetResult(Activity activity, string checkoutResult)
    {
        activity?.SetTag(ResultTag, checkoutResult);
    }

    public static void SetFailure(Activity activity, string stage, string reasonCode)
    {
        activity?.SetTag(StageTag, stage);
        activity?.SetTag(ResultTag, ResultFailure);
        activity?.SetTag(FailureReasonTag, reasonCode);
    }

    /// <summary>
    /// Records a checkout stage attempt (called at the start of a stage, before outcome is known).
    /// </summary>
    /// <param name="stage">The checkout stage (prepare, payment, persist_order, move_items, finalize)</param>
    public static void RecordStageAttempt(string stage)
    {
        TagList tags = new()
        {
            { "stage", stage }
        };

        AttemptsCounter.Add(1, tags);
    }

    /// <summary>
    /// Records the completion of a checkout stage with outcome (success or failure).
    /// </summary>
    /// <param name="stage">The checkout stage</param>
    /// <param name="outcome">success or failure</param>
    /// <param name="reasonCode">Optional failure reason code</param>
    /// <param name="subsystem">Optional subsystem identifier (basket, inventory, payment_provider, order_processing)</param>
    public static void RecordStageCompletion(string stage, string outcome, string reasonCode = null, string subsystem = null)
    {
        TagList tags = new()
        {
            { "stage", stage },
            { "outcome", outcome }
        };

        if (!string.IsNullOrWhiteSpace(reasonCode))
        {
            tags.Add("reason_code", reasonCode);
        }

        if (!string.IsNullOrWhiteSpace(subsystem))
        {
            tags.Add("subsystem", subsystem);
        }

        StageCompletionsCounter.Add(1, tags);
    }

    public static void RecordStageDuration(double durationMs, string checkoutMode, string stage, string outcome,
        string paymentMethodSystemName = null)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) },
            { "stage", stage },
            { "outcome", outcome }
        };

        if (string.Equals(stage, "payment", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(paymentMethodSystemName))
        {
            tags.Add("payment.method.system", paymentMethodSystemName);
        }

        StageDurationHistogram.Record(durationMs, tags);

        // Also record stage completion for success rate tracking
        RecordStageCompletion(stage, outcome);
    }

    public static IDisposable TrackInflightRequest(string checkoutMode)
    {
        var normalizedMode = NormalizeMode(checkoutMode);
        TagList tags = new()
        {
            { "checkout_mode", normalizedMode }
        };

        InflightRequestsCounter.Add(1, tags);

        return new InflightRequestScope(tags);
    }

    private static string NormalizeMode(string checkoutMode)
    {
        return string.IsNullOrWhiteSpace(checkoutMode) ? ModeStandard : checkoutMode;
    }

    private sealed class InflightRequestScope : IDisposable
    {
        private readonly TagList _tags;
        private bool _disposed;

        public InflightRequestScope(TagList tags)
        {
            _tags = tags;
        }

        public void Dispose()
        {
            if (_disposed)
                return;

            InflightRequestsCounter.Add(-1, _tags);
            _disposed = true;
        }
    }
}
