Rails.application.routes.draw do
  # Signup
  resource :registration, only: [ :new, :create ]
  get "signup", to: "registrations#new"

  # Login
  resource :session, except: %i[ new ]
  get "login", to: "sessions#new", as: :new_session

  resources :passwords, param: :token

  # Playlists
  resources :playlists, only: [ :create ]

  # Test APIs (remove in production)
  get 'test/apis', to: 'test#test_apis' if Rails.env.development?
  get 'test/spotify-user', to: 'test#get_spotify_user_info' if Rails.env.development?
  post 'test/create-playlist', to: 'test#create_test_playlist' if Rails.env.development?

  # Spotify OAuth
  get 'auth/spotify', to: 'spotify_auth#authorize'
  get 'auth/spotify/callback', to: 'spotify_auth#callback'

  # Home Page
  root "pages#home"

  # Dashboard Page
  get "dashboard", to: "pages#dashboard", as: :dashboard

  get "up" => "rails/health#show"
end
