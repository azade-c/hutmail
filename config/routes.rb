Rails.application.routes.draw do
  resource :user, only: %i[new create]
  resource :session

  resources :vessels, only: %i[index new create show] do
    resources :mail_accounts, only: %i[index new create], module: :vessels
    resources :bundles, only: :index, module: :vessels
    resource :dispatch_preview, only: :show
    resource :dispatch, only: :create, module: :vessels
    resource :budget_reset, only: :create, module: :vessels
    resource :settings, only: %i[edit update]
  end

  resources :mail_accounts, only: %i[show edit update destroy] do
    resource :collection, only: :create
  end

  resources :bundles, only: :show

  # Public trace of a vessel, guarded by an unguessable token rather than a
  # login: it is meant to be shared with family ashore, not indexed. The path is
  # French because this is the only URL anyone outside the crew ever sees.
  # The constraint mirrors Vessel::Tracking::TOKEN_FORMAT.
  resources :tracks, only: :show, path: "suivi", param: :token,
    constraints: { token: /[A-Za-z0-9]{16,64}/ }

  resource :home, only: :show, controller: "home"
  resource :guide, only: :show
  resource :commands, only: :show
  resource :verification, only: :show

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
