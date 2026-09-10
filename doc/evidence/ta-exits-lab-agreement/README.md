# Exits agreement evidence

The screenshots show the agreement section of the real `/lab/exits` page in
headless Chromium, using the app's existing lab styles. They are synthetic
states, not measurements of generated quality.

- `empty.png`: no draws in either set.
- `below.png`: an insufficient tuning set with an openable suspect and miss;
  unavailable and no-eligible-verdict rows remain distinct.
- `established.png`: tuning reaches `Story::Scoreboard::MIN_VERDICTS`; the held-out
  set remains labelled and insufficient on its own.
- Matching `.txt` files are browser text; `rake-*.txt` prints the same fixtures
  through `eval:exits_alignment`. `browser-checks.json` records the assertions
  and links, which were also opened successfully.
- `rails-test.txt`, `rubocop.txt`, `zeitwerk.txt`, and `brakeman.txt` record the
  required validation commands. The Rails suite includes the engine sweep.

`capture.mjs` drives Chromium over CDP directly with Node's built-in WebSocket,
without npm dependencies or an app build step. Run it from an isolated treehouse
worktree after preparing its database. It checks the chosen ports with `ss`,
records the started PIDs in `processes.json`, starts the app through `bin/dev`,
and stops only the processes it started. It backs up and restores that worktree's
development database around `seed.rb`; it never accesses the primary checkout's
database. `ports.txt` records the free-port check. The browser and app were stopped
after capture.

The implementation's attribution and rejected alternatives live in
`app/models/lab/exits/agreement.rb`. In particular, repeated draws cannot multiply
one name judgement into enough verdicts to establish agreement.
