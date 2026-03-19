using System.Diagnostics;
using Nop.Core.Domain.Customers;
using Nop.Core.Domain.Orders;
using Nop.Core.Domain.Shipping;
using Nop.Core.Observability;
using Nop.Services.Orders;
using Nop.Services.Payments;

namespace Nop.Web.Framework.Infrastructure.Observability;

/// <summary>
/// Adds checkout root-span instrumentation at the service boundary without changing order orchestration behavior.
/// </summary>
public class ObservedOrderProcessingService : IOrderProcessingService
{
    protected readonly OrderProcessingService _orderProcessingService;

    public ObservedOrderProcessingService(OrderProcessingService orderProcessingService)
    {
        _orderProcessingService = orderProcessingService;
    }

    public virtual async Task<PlaceOrderResult> PlaceOrderAsync(ProcessPaymentRequest processPaymentRequest)
    {
        var checkoutMode = NopTelemetry.GetCheckoutMode();

        using var checkoutActivity = NopTelemetry.StartCheckoutActivity("nop.checkout.place_order", checkoutMode, "place_order");
        NopTelemetry.SetCheckoutResult(checkoutActivity, NopTelemetry.CheckoutResultSuccess);

        if (!string.IsNullOrWhiteSpace(processPaymentRequest?.PaymentMethodSystemName))
            checkoutActivity?.SetTag("payment.method.system", processPaymentRequest.PaymentMethodSystemName);

        try
        {
            var result = await _orderProcessingService.PlaceOrderAsync(processPaymentRequest);

            if (!result.Success)
            {
                NopTelemetry.SetCheckoutResult(checkoutActivity, NopTelemetry.CheckoutResultFailure);
                checkoutActivity?.SetStatus(ActivityStatusCode.Error);
            }

            return result;
        }
        catch
        {
            NopTelemetry.SetCheckoutResult(checkoutActivity, NopTelemetry.CheckoutResultFailure);
            checkoutActivity?.SetStatus(ActivityStatusCode.Error);
            throw;
        }
    }

    public virtual Task CheckOrderStatusAsync(Order order)
    {
        return _orderProcessingService.CheckOrderStatusAsync(order);
    }

    public virtual Task UpdateOrderTotalsAsync(UpdateOrderParameters updateOrderParameters)
    {
        return _orderProcessingService.UpdateOrderTotalsAsync(updateOrderParameters);
    }

    public virtual Task DeleteOrderAsync(Order order)
    {
        return _orderProcessingService.DeleteOrderAsync(order);
    }

    public virtual Task<IEnumerable<string>> ProcessNextRecurringPaymentAsync(RecurringPayment recurringPayment, ProcessPaymentResult paymentResult = null)
    {
        return _orderProcessingService.ProcessNextRecurringPaymentAsync(recurringPayment, paymentResult);
    }

    public virtual Task<IList<string>> CancelRecurringPaymentAsync(RecurringPayment recurringPayment)
    {
        return _orderProcessingService.CancelRecurringPaymentAsync(recurringPayment);
    }

    public virtual Task<bool> CanCancelRecurringPaymentAsync(Customer customerToValidate, RecurringPayment recurringPayment)
    {
        return _orderProcessingService.CanCancelRecurringPaymentAsync(customerToValidate, recurringPayment);
    }

    public virtual Task<bool> CanRetryLastRecurringPaymentAsync(Customer customer, RecurringPayment recurringPayment)
    {
        return _orderProcessingService.CanRetryLastRecurringPaymentAsync(customer, recurringPayment);
    }

    public virtual Task ShipAsync(Shipment shipment, bool notifyCustomer)
    {
        return _orderProcessingService.ShipAsync(shipment, notifyCustomer);
    }

    public virtual Task ReadyForPickupAsync(Shipment shipment, bool notifyCustomer)
    {
        return _orderProcessingService.ReadyForPickupAsync(shipment, notifyCustomer);
    }

    public virtual Task DeliverAsync(Shipment shipment, bool notifyCustomer)
    {
        return _orderProcessingService.DeliverAsync(shipment, notifyCustomer);
    }

    public virtual bool CanCancelOrder(Order order)
    {
        return _orderProcessingService.CanCancelOrder(order);
    }

    public virtual Task CancelOrderAsync(Order order, bool notifyCustomer)
    {
        return _orderProcessingService.CancelOrderAsync(order, notifyCustomer);
    }

    public virtual bool CanMarkOrderAsAuthorized(Order order)
    {
        return _orderProcessingService.CanMarkOrderAsAuthorized(order);
    }

    public virtual Task MarkAsAuthorizedAsync(Order order)
    {
        return _orderProcessingService.MarkAsAuthorizedAsync(order);
    }

    public virtual Task<bool> CanCaptureAsync(Order order)
    {
        return _orderProcessingService.CanCaptureAsync(order);
    }

    public virtual Task<IList<string>> CaptureAsync(Order order)
    {
        return _orderProcessingService.CaptureAsync(order);
    }

    public virtual bool CanMarkOrderAsPaid(Order order)
    {
        return _orderProcessingService.CanMarkOrderAsPaid(order);
    }

    public virtual Task MarkOrderAsPaidAsync(Order order)
    {
        return _orderProcessingService.MarkOrderAsPaidAsync(order);
    }

    public virtual Task<bool> CanRefundAsync(Order order)
    {
        return _orderProcessingService.CanRefundAsync(order);
    }

    public virtual Task<IList<string>> RefundAsync(Order order)
    {
        return _orderProcessingService.RefundAsync(order);
    }

    public virtual bool CanRefundOffline(Order order)
    {
        return _orderProcessingService.CanRefundOffline(order);
    }

    public virtual Task RefundOfflineAsync(Order order)
    {
        return _orderProcessingService.RefundOfflineAsync(order);
    }

    public virtual Task<IList<string>> PartiallyRefundAsync(Order order, decimal amountToRefund)
    {
        return _orderProcessingService.PartiallyRefundAsync(order, amountToRefund);
    }

    public virtual Task<bool> CanPartiallyRefundAsync(Order order, decimal amountToRefund)
    {
        return _orderProcessingService.CanPartiallyRefundAsync(order, amountToRefund);
    }

    public virtual bool CanPartiallyRefundOffline(Order order, decimal amountToRefund)
    {
        return _orderProcessingService.CanPartiallyRefundOffline(order, amountToRefund);
    }

    public virtual Task PartiallyRefundOfflineAsync(Order order, decimal amountToRefund)
    {
        return _orderProcessingService.PartiallyRefundOfflineAsync(order, amountToRefund);
    }

    public virtual Task<bool> CanVoidAsync(Order order)
    {
        return _orderProcessingService.CanVoidAsync(order);
    }

    public virtual Task<IList<string>> VoidAsync(Order order)
    {
        return _orderProcessingService.VoidAsync(order);
    }

    public virtual bool CanVoidOffline(Order order)
    {
        return _orderProcessingService.CanVoidOffline(order);
    }

    public virtual Task VoidOfflineAsync(Order order)
    {
        return _orderProcessingService.VoidOfflineAsync(order);
    }

    public virtual Task<IList<string>> ReOrderAsync(Order order)
    {
        return _orderProcessingService.ReOrderAsync(order);
    }

    public virtual Task<bool> IsReturnRequestAllowedAsync(Order order)
    {
        return _orderProcessingService.IsReturnRequestAllowedAsync(order);
    }

    public virtual Task<bool> ValidateMinOrderSubtotalAmountAsync(IList<ShoppingCartItem> cart)
    {
        return _orderProcessingService.ValidateMinOrderSubtotalAmountAsync(cart);
    }

    public virtual Task<bool> ValidateMinOrderTotalAmountAsync(IList<ShoppingCartItem> cart)
    {
        return _orderProcessingService.ValidateMinOrderTotalAmountAsync(cart);
    }

    public virtual Task<bool> IsPaymentWorkflowRequiredAsync(IList<ShoppingCartItem> cart, bool? useRewardPoints = null)
    {
        return _orderProcessingService.IsPaymentWorkflowRequiredAsync(cart, useRewardPoints);
    }

    public virtual Task<DateTime?> GetNextPaymentDateAsync(RecurringPayment recurringPayment)
    {
        return _orderProcessingService.GetNextPaymentDateAsync(recurringPayment);
    }

    public virtual Task<int> GetCyclesRemainingAsync(RecurringPayment recurringPayment)
    {
        return _orderProcessingService.GetCyclesRemainingAsync(recurringPayment);
    }

    public virtual Task<ProcessPaymentRequest> GetProcessPaymentRequestAsync()
    {
        return _orderProcessingService.GetProcessPaymentRequestAsync();
    }

    public virtual Task SetProcessPaymentRequestAsync(ProcessPaymentRequest processPaymentRequest, bool useNewOrderGuid = false)
    {
        return _orderProcessingService.SetProcessPaymentRequestAsync(processPaymentRequest, useNewOrderGuid);
    }
}
