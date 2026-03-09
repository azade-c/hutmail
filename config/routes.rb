Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :vessels, only: [ :new, :create ]

  resources :mail_accounts
  resources :bundles, only: [ :index, :show ]

  resource :settings, only: [ :edit, :update ]

  get "up" => "rails/health#show", as: :rails_health_check
  get "dashboard" => "dashboard#show", as: :dashboard
  get "home" => "home#show", as: :home

  root "home#show"
end
