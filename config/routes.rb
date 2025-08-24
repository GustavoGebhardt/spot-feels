Rails.application.routes.draw do
  # Signup
  resource :registration, only: [ :new, :create ]
  get "signup", to: "registrations#new"

  # Login
  resource :session, except: %i[ new ]
  get "login", to: "sessions#new", as: :new_session

  resources :passwords, param: :token

  # Home Page
  root "pages#home"

  # Dashboard Page
  get "dashboard", to: "pages#dashboard", as: :dashboard

  get "up" => "rails/health#show"
end
