Rails.application.routes.draw do
  root "today#show"

  get "today", to: "today#show", as: :today
  resources :batches, only: %i[index show]
  resources :work_items, only: %i[index show], path: "tickets"
  resources :time_drafts, only: %i[index update], path: "harvest" do
    collection do
      post :generate
      post :approve_all
      post :send_approved
    end
  end
  resource :settings, only: %i[show update]
  resources :projects, only: %i[create update]
  resources :people, only: %i[create]
  post "attention/heartbeat", to: "attention#heartbeat", as: :attention_heartbeat

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
      resources :attention, only: :create
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
