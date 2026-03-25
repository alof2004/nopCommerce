using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace Nop.Core.Observability;

/// <summary>
/// Repository write telemetry for checkout-specific persistence diagnostics.
/// </summary>
public static class RepositoryTelemetry
{
    private static readonly Histogram<double> RepositoryWriteDurationHistogram =
        NopTelemetry.Meter.CreateHistogram<double>("nop.checkout.repository_write_duration_ms", "ms");

    public static void RecordWriteDuration(double durationMs, string operation, string entityGroup, string outcome)
    {
        var checkoutMode = Activity.Current?.GetBaggageItem(CheckoutTelemetry.ModeTag);
        if (string.IsNullOrWhiteSpace(checkoutMode))
            return;

        TagList tags = new()
        {
            { "checkout_mode", checkoutMode },
            { "operation", operation },
            { "entity_group", NormalizeEntityGroup(entityGroup) },
            { "outcome", outcome }
        };

        RepositoryWriteDurationHistogram.Record(durationMs, tags);
    }

    private static string NormalizeEntityGroup(string entityGroup)
    {
        return string.IsNullOrWhiteSpace(entityGroup) ? "other" : entityGroup;
    }
}
