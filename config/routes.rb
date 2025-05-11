Rails.application.routes.draw do
  resources :facebook_syncs
  resources :error_logs
  mount MissionControl::Jobs::Engine, at: "/jobs"
  get "metrics/index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  post "track/identify", to: "tracking#identify"
  post "track/event", to: "tracking#event"

  post "metrics/event", to: "metrics#event"
  # Add the UI routes with basic HTTP authentication
  get "metrics", to: "metrics#index"

  get "facebook_syncs", to: "facebook_syncs#index"

  # Hubspot routes
  resources :hubspot, only: [ :index ] do
    collection do
      post :sync
      post :run_console
      post :schema_update
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "metrics#index"
end
