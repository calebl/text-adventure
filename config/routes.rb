Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The browser interface only *plays* stories. Generating them is still
  # `rake game:new[premise]`.
  resources :playthroughs, only: [ :index, :create, :show ] do
    resources :turns, only: [ :create ]

    # Server-sent events. A GET because that is all EventSource can issue.
    get "narration", to: "narrations#show"
  end

  root "playthroughs#index"
end
