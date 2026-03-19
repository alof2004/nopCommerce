using System.Diagnostics;
using System.Linq;
using OpenTelemetry;

namespace Nop.Web.Infrastructure.Observability;

/// <summary>
/// Removes sensitive span tags before export so checkout telemetry stays structural only.
/// </summary>
public sealed class SensitiveActivitySanitizingProcessor : BaseProcessor<Activity>
{
    private static readonly string[] ExactSensitiveTagNames =
    [
        "client.address",
        "customer.email",
        "customer.id",
        "customer.ip",
        "customer.phone",
        "customer.vat_number",
        "exception.message",
        "exception.stacktrace",
        "http.client_ip",
        "http.target",
        "network.peer.address",
        "payment.gateway.result",
        "payment.masked_card_number",
        "payment.transaction.id",
        "url.full",
        "url.query"
    ];

    public override void OnEnd(Activity data)
    {
        foreach (var tagName in ExactSensitiveTagNames)
            data.SetTag(tagName, null);

        var sensitiveTagNames = data.Tags
            .Select(tag => tag.Key)
            .Where(IsSensitiveTag)
            .ToArray();

        foreach (var tagName in sensitiveTagNames)
            data.SetTag(tagName, null);
    }

    private static bool IsSensitiveTag(string tagName)
    {
        if (string.IsNullOrWhiteSpace(tagName))
            return false;

        if (tagName.StartsWith("billing.address.", StringComparison.OrdinalIgnoreCase) ||
            tagName.StartsWith("checkout.attributes.", StringComparison.OrdinalIgnoreCase) ||
            tagName.StartsWith("payment.authorization.", StringComparison.OrdinalIgnoreCase) ||
            tagName.StartsWith("payment.card.", StringComparison.OrdinalIgnoreCase) ||
            tagName.StartsWith("pickup.address.", StringComparison.OrdinalIgnoreCase) ||
            tagName.StartsWith("shipping.address.", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return tagName.EndsWith(".email", StringComparison.OrdinalIgnoreCase) ||
               tagName.EndsWith(".ip", StringComparison.OrdinalIgnoreCase) ||
               tagName.EndsWith(".phone", StringComparison.OrdinalIgnoreCase) ||
               tagName.EndsWith(".xml", StringComparison.OrdinalIgnoreCase);
    }
}
