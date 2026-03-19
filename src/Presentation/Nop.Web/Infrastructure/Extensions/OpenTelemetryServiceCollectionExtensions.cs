using System.IO;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Nop.Core.Observability;
using Nop.Web.Infrastructure.Observability;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace Nop.Web.Infrastructure.Extensions;

public static class OpenTelemetryServiceCollectionExtensions
{
    private static readonly HashSet<string> StaticAssetExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".avif",
        ".bmp",
        ".css",
        ".gif",
        ".ico",
        ".jpeg",
        ".jpg",
        ".js",
        ".map",
        ".png",
        ".svg",
        ".webp",
        ".woff",
        ".woff2"
    };

    public static IServiceCollection AddNopOpenTelemetry(this IServiceCollection services, IHostEnvironment environment)
    {
        var otlpEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");

        services.AddOpenTelemetry()
            .ConfigureResource(resource => resource.AddService(NopTelemetry.ServiceName))
            .WithTracing(tracing =>
            {
                tracing
                    .AddProcessor(new SensitiveActivitySanitizingProcessor())
                    .AddSource(NopTelemetry.ActivitySourceName)
                    .AddAspNetCoreInstrumentation(options =>
                    {
                        options.RecordException = false;
                        options.Filter = context => !IsStaticAssetRequest(context.Request.Path);
                    })
                    .AddHttpClientInstrumentation(options => options.RecordException = false);

                if (!string.IsNullOrWhiteSpace(otlpEndpoint))
                    tracing.AddOtlpExporter();
                else if (environment.IsDevelopment())
                    tracing.AddConsoleExporter();
            })
            .WithMetrics(metrics =>
            {
                metrics
                    .AddMeter(NopTelemetry.MeterName)
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation();

                if (!string.IsNullOrWhiteSpace(otlpEndpoint))
                    metrics.AddOtlpExporter();
                else if (environment.IsDevelopment())
                    metrics.AddConsoleExporter();
            });

        return services;
    }

    private static bool IsStaticAssetRequest(PathString path)
    {
        if (!path.HasValue)
            return false;

        var extension = Path.GetExtension(path.Value);
        return !string.IsNullOrEmpty(extension) && StaticAssetExtensions.Contains(extension);
    }
}
