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

    # THE CAPTAIN'S VERDICT ON ONE TURN, addressed by the turn rather than by a
    # row id -- there is at most one per (playthrough, scene), so recording and
    # amending are the same POST and the play page never has to carry an id it
    # would not have before the first click. Drawn unconditionally and gated in
    # the controller, like the debug view below and on the same flag.
    resources :feedbacks, only: [ :create, :destroy ], param: :scene_id

    # The window into the machine. Drawn unconditionally and gated in the
    # controller, so the path helper exists in every environment and the page
    # exists in none but the ones `Playthrough::Debug.enabled?` allows.
    get "debug", to: "debug#show"

    # THE MACHINERY BEHIND ONE TURN, fetched a turn at a time by the panel on
    # the play page. Addressed by the turn rather than by an id of its own, like
    # the verdict above and for the same reason: there is exactly one of these
    # per (playthrough, scene) and it is resolved against
    # `Playthrough#scene_chain` rather than found. Drawn unconditionally and
    # gated on the same flag as the two above.
    get "machinery/:scene_id", to: "machinery#show", as: :machinery
  end

  root "playthroughs#index"
end
