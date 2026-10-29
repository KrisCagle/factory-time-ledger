Rails.application.routes.draw do
  root "today#show"

  get "today", to: "today#show", as: :today
  resources :batches, only: %i[index show]
  resources :work_items, only: %i[index show create], path: "tickets"
  resources :time_drafts, only: %i[index update], path: "harvest" do
    member do
      post :verify
      post :undo
    end
    collection do
      post :generate
      post :approve_all
      post :send_approved
    end
  end
  resource :settings, only: %i[show update]
  resources :projects, only: %i[create update]
  resource :harvest_connection, only: [] do
    post :check
    post :load_projects
    post :test_entry
  end
  resource :scarif_connection, only: :update do
    post :check
    post :sync
  end
  resources :people, only: %i[create]
  resource :demo_data, only: :destroy, controller: "demo_data"
  post "attention/heartbeat", to: "attention#heartbeat", as: :attention_heartbeat

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
      resources :attention, only: :create
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
