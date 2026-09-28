# prompt-2026-09-28

The main prompt corpus, re-bought at four repetitions on the shipped model
after an arrival stopped reading the world's `last_protagonist_visit` as one
game's memory (it reads the game's own scene chain now).

No prompt text changed. One staged request did: the `move` case opens in the
Causeway Court, walks to the Tide Post and walks back, and it now gets the
existing return branch rather than the first-arrival branch. The staging never
stamped the room a game opens in, so the previous baseline, `prompt-2026-09-26`,
had measured a return narrated as a discovery.

`rake eval:prompt_compare BEFORE=prompt-2026-09-26 AFTER=prompt-2026-09-28`
is recorded below.

Every check reads NOISE against `prompt-2026-09-26`. Median and p95 latency
read REAL slower (1.57s -> 1.79s, 1.99s -> 2.46s), which is provider timing on
the day and not something the change can move.
