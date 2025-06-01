require Rails.root.join("lib", "middleware", "error_tracking_middleware")

Rails.application.configure do
  config.middleware.use Middleware::ErrorTrackingMiddleware
end
