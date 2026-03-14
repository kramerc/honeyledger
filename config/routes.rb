Rails.application.routes.draw do
  devise_for :users

  resources :accounts do
    resources :transactions, only: %i[ index ]
  end
  resources :categories
  resources :currencies
  resources :transactions

  # SimpleFIN integration routes
  namespace :simplefin do
    resources :accounts, only: [] do
      member do
        post :link
        delete :unlink
      end
    end
    resource :connection, only: %i[ new create show destroy ] do
      member do
        post :refresh
      end
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Serve coverage reports in development
  if Rails.env.development?
    get "/coverage", to: redirect("/coverage/index.html")
    mount Rack::Directory.new(Rails.root.join("coverage").to_s), at: "/coverage"
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
end
