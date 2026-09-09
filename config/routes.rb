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

    # THE PICTURE OF THE WORLD, with the party on it. Same gate and same layout
    # as `debug` above; see `MapController` for why there are two ways in.
    get "map", to: "map#show"
  end

  # THE SAME PICTURE WITHOUT A GAME ON IT -- the durable world alone, which is
  # what there is to look at after `rake game:new` and before anybody has
  # played. Not `resources :stories`: the browser interface does not have a
  # story resource and this is not the beginning of one, it is the debug
  # surface's second door.
  #
  # This is where a browser debug surface is documented rather than the README,
  # and it is documented by pointing: `Story::Map`'s header says what the page
  # draws, `MapController`'s says who links here and which of those links
  # carries a gate of its own. Nothing is reachable any way in unless
  # `Playthrough::Debug.enabled?`, the flag `MapController` gates this endpoint
  # on: on in development, `TA_DEBUG_VIEW` anywhere else. Take a world's id from
  # `rake game:list` to type the URL directly.
  get "stories/:story_id/map", to: "map#show", as: :story_map

  # THE REALIZATION LAB -- a kind of place typed, drawn, watched in sequence,
  # judged, and counted against what the captain said the picks should be.
  #
  # Drawn unconditionally and gated in the controllers, like the debug surface
  # above and on the same flag (`Playthrough::Debug.enabled?`), so the path
  # helpers exist in every environment and the pages exist in none but the ones
  # that flag allows.
  #
  # THE ONE THING THESE ROUTES ENFORCE is that a GET never buys a model call:
  # drawing a sample is `POST /lab/kinds/:kind_id/samples` and nothing else in
  # the app reaches `Lab::Realization::Runner`. `Lab::Realization`'s header is
  # the design; `Lab::SamplesController`'s says why the spend is a POST.
  #
  # AND THE EXITS LAB IS THE SAME RULE ONE NAMESPACE DOWN: drawing is
  # `POST /lab/exits/vantages/:vantage_id/samples` and nothing else in the app
  # reaches `Lab::Exits::Runner`. Its own segment rather than a fourth resource
  # beside `kinds`, because both labs draw a thing called a SAMPLE and two
  # `lab_sample_path` helpers cannot both exist -- and because the captain asked
  # for the page at `/lab/exits`, which the alias below is.
  namespace :lab do
    resources :kinds, only: [ :index, :show, :create, :update, :destroy ] do
      resources :samples, only: [ :create ]
    end
    resources :samples, only: [ :show, :update ]

    get "exits", to: "exits/vantages#index", as: :exits

    namespace :exits do
      resources :vantages, only: [ :index, :show, :create, :update, :destroy ] do
        resources :samples, only: [ :create ]
        # ONE ENDPOINT FOR BOTH HALVES OF WHAT HE SAYS ABOUT A PLACE, and it is a
        # POST because the row may not exist yet: he types an expectation for a
        # place no draw has named, or judges one a draw just did, and
        # `Lab::Exits::Vantage#judge!` finds or creates the row by its natural
        # key either way. `Lab::Exits::Judgement`'s header has why the two halves
        # share a row -- and neither half buys a model call, so the POST spends
        # nothing.
        resources :judgements, only: [ :create ]
      end
      resources :samples, only: [ :show, :update ]
    end
  end

  root "playthroughs#index"
end
