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

    public static readonly ActivitySource ActivitySource = new(ActivitySourceName);
    public static readonly Meter Meter = new(MeterName);
}
