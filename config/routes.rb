Rails.application.routes.draw do
  resource :user, only: %i[new create]
  resource :session

  resources :vessels, only: %i[index new create show] do
    resources :mail_accounts
    resources :bundles, only: %i[index show]
    resource :settings, only: %i[edit update]
  end

  resource :home, only: :show, controller: "home"

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
