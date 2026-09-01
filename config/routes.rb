Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The browser interface only *plays* stories. Generating them is still
  # `rake game:new[premise]`.
  resources :playthroughs, only: [ :index, :create, :show ] do
    # A turn is enqueued here and broadcast back over Action Cable by
    # NarrationJob, so there is no streaming endpoint to route to any more.
    resources :turns, only: [ :create ]

    # The window into the machine. Drawn unconditionally and gated in the
    # controller, so the path helper exists in every environment and the page
    # exists in none but the ones `Playthrough::Debug.enabled?` allows.
    get "debug", to: "debug#show"
  end

  root "playthroughs#index"
end
