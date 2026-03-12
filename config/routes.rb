Rails.application.routes.draw do
  resource :user, only: %i[new create]
  resource :session

  resources :vessels, only: %i[index new create show] do
    resources :mail_accounts, only: %i[index new create], module: :vessels
    resources :bundles, only: :index, module: :vessels
    resource :dispatch_preview, only: :show
    resource :dispatch, only: :create, module: :vessels
    resource :settings, only: %i[edit update]
  end

  resources :mail_accounts, only: %i[show edit update destroy] do
    resource :collection, only: :create
  end

  resources :bundles, only: :show

  resource :home, only: :show, controller: "home"

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
