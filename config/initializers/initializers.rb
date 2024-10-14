Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "localhost:3000", "https://analytics.clever-builds.com", "https://analytics.clevertinyhomes.com"
    resource "*", headers: :any, methods: [ :get, :post, :patch, :put ]
  end
end
