using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace Nop.Core.Observability;

/// <summary>
/// Shared OpenTelemetry primitives for nopCommerce custom spans and metrics.
/// </summary>
public static class NopTelemetry
{
    public const string ServiceName = "nopcommerce-web";
    public const string ActivitySourceName = "NopCommerce.Observability";
    public const string MeterName = "NopCommerce.Metrics";

    public const string CheckoutModeTag = "checkout.mode";
    public const string CheckoutResultTag = "checkout.result";
    public const string CheckoutStageTag = "checkout.stage";
    public const string CheckoutFailureReasonTag = "failure.reason_code";

    public const string CheckoutModeStandard = "standard";
    public const string CheckoutModeOpc = "opc";
    public const string CheckoutResultSuccess = "success";
    public const string CheckoutResultFailure = "failure";

    public static readonly ActivitySource ActivitySource = new(ActivitySourceName);
    public static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> CheckoutFailuresCounter =
        Meter.CreateCounter<long>("nop.checkout.failures_total");

    private static readonly Histogram<double> CheckoutStageDurationHistogram =
        Meter.CreateHistogram<double>("nop.checkout.stage_duration_ms", "ms");

    public static string GetCheckoutMode()
    {
        return Activity.Current?.GetBaggageItem(CheckoutModeTag) ?? CheckoutModeStandard;
    }

    public static void SetCheckoutMode(string checkoutMode)
    {
        if (string.IsNullOrWhiteSpace(checkoutMode))
            checkoutMode = CheckoutModeStandard;

        Activity.Current?.SetBaggage(CheckoutModeTag, checkoutMode);
    }

    public static Activity StartCheckoutActivity(string name, string checkoutMode, string stage)
    {
        var activity = ActivitySource.StartActivity(name, ActivityKind.Internal);

        SetCheckoutModeTag(activity, checkoutMode);
        activity?.SetTag(CheckoutStageTag, stage);

        return activity;
    }

    public static void SetCheckoutModeTag(Activity activity, string checkoutMode)
    {
        activity?.SetTag(CheckoutModeTag, string.IsNullOrWhiteSpace(checkoutMode) ? CheckoutModeStandard : checkoutMode);
    }

    public static void SetCheckoutResult(Activity activity, string checkoutResult)
    {
        activity?.SetTag(CheckoutResultTag, checkoutResult);
    }

    public static void SetCheckoutFailure(Activity activity, string stage, string reasonCode)
    {
        activity?.SetTag(CheckoutStageTag, stage);
        activity?.SetTag(CheckoutResultTag, CheckoutResultFailure);
        activity?.SetTag(CheckoutFailureReasonTag, reasonCode);
    }

    public static void RecordCheckoutFailure(string checkoutMode, string stage, string reasonCode)
    {
        TagList tags = new()
        {
            { "checkout_mode", string.IsNullOrWhiteSpace(checkoutMode) ? CheckoutModeStandard : checkoutMode },
            { "stage", stage },
            { "reason_code", reasonCode }
        };

        CheckoutFailuresCounter.Add(1, tags);
    }

    public static void RecordCheckoutStageDuration(double durationMs, string checkoutMode, string stage, string outcome,
        string paymentMethodSystemName = null)
    {
        TagList tags = new()
        {
            { "checkout_mode", string.IsNullOrWhiteSpace(checkoutMode) ? CheckoutModeStandard : checkoutMode },
            { "stage", stage },
            { "outcome", outcome }
        };

        if (string.Equals(stage, "payment", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(paymentMethodSystemName))
        {
            tags.Add("payment.method.system", paymentMethodSystemName);
        }

        CheckoutStageDurationHistogram.Record(durationMs, tags);
    }
}
