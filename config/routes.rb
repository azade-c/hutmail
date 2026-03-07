Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :mail_accounts
  resources :bundles, only: [ :index, :show ]

  resource :settings, only: [ :edit, :update ]

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
end
