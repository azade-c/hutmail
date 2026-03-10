Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :vessels, only: [ :new, :create ]

  resources :mail_accounts
  resources :bundles, only: [ :index, :show ]

  resource :settings, only: [ :edit, :update ]
  resource :dashboard, only: :show, controller: "dashboard"
  resource :home, only: :show, controller: "home"

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
