using Nop.Core;

namespace Nop.Core.Observability;

/// <summary>
/// Represents a checkout validation failure with a stable observability reason code.
/// </summary>
public sealed class CheckoutValidationException : NopException
{
    public CheckoutValidationException(string reasonCode, string message)
        : base(message)
    {
        ReasonCode = reasonCode;
    }

    public string ReasonCode { get; }
}
