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

    private static readonly Histogram<double> CompletionTimeHistogram =
        NopTelemetry.Meter.CreateHistogram<double>("nop.checkout.completion_time_ms", "ms");

    private static readonly UpDownCounter<long> ActiveCheckoutsCounter =
        NopTelemetry.Meter.CreateUpDownCounter<long>("nop.checkout.active");

    private static readonly Counter<long> RetryAttemptsCounter =
        NopTelemetry.Meter.CreateCounter<long>("nop.checkout.retry_attempts_total");

    public const string IsRetryTag = "is_retry";

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
    public static void RecordStageAttempt(string stage, string checkoutMode)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) },
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
    public static void RecordStageCompletion(string stage, string checkoutMode, string outcome, string reasonCode = null, string subsystem = null)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) },
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
        string paymentMethodSystemName = null, string reasonCode = null, string subsystem = null, bool recordCompletion = true)
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

        if (recordCompletion)
            RecordStageCompletion(stage, checkoutMode, outcome, reasonCode, subsystem);
    }

    public static void RecordCompletionTime(double durationMs, string checkoutMode, string outcome,
        string paymentMethodSystemName = null)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) },
            { "outcome", outcome }
        };

        if (!string.IsNullOrWhiteSpace(paymentMethodSystemName))
        {
            tags.Add("payment.method.system", paymentMethodSystemName);
        }

        if (IsRetry())
        {
            tags.Add("is_retry", "true");
        }

        CompletionTimeHistogram.Record(durationMs, tags);
    }

    public static void IncrementActiveCheckouts(string checkoutMode)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) }
        };

        ActiveCheckoutsCounter.Add(1, tags);
    }

    public static void DecrementActiveCheckouts(string checkoutMode)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) }
        };

        ActiveCheckoutsCounter.Add(-1, tags);
    }

    /// <summary>
    /// Marks the current checkout attempt as a retry in the activity baggage.
    /// Call this at the start of checkout if retry is detected (e.g., recent failed attempt for same cart).
    /// </summary>
    public static void MarkAsRetry()
    {
        Activity.Current?.SetBaggage(IsRetryTag, "true");
    }

    /// <summary>
    /// Returns true if the current checkout is marked as a retry.
    /// </summary>
    public static bool IsRetry()
    {
        return Activity.Current?.GetBaggageItem(IsRetryTag) == "true";
    }

    /// <summary>
    /// Records a retry attempt metric.
    /// </summary>
    /// <param name="checkoutMode">The checkout mode</param>
    /// <param name="reason">Optional reason for retry (e.g., payment_failed, validation_error)</param>
    public static void RecordRetryAttempt(string checkoutMode, string reason = null)
    {
        TagList tags = new()
        {
            { "checkout_mode", NormalizeMode(checkoutMode) }
        };

        if (!string.IsNullOrWhiteSpace(reason))
        {
            tags.Add("retry_reason", reason);
        }

        RetryAttemptsCounter.Add(1, tags);
    }

    private static string NormalizeMode(string checkoutMode)
    {
        return string.IsNullOrWhiteSpace(checkoutMode) ? ModeStandard : checkoutMode;
    }
}
