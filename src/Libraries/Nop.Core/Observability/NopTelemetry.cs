using System.Diagnostics;

namespace Nop.Core.Observability;

/// <summary>
/// Shared OpenTelemetry primitives for nopCommerce custom spans.
/// </summary>
public static class NopTelemetry
{
    public const string ServiceName = "nopcommerce-web";
    public const string ActivitySourceName = "NopCommerce.Observability";

    public static readonly ActivitySource ActivitySource = new(ActivitySourceName);
}
