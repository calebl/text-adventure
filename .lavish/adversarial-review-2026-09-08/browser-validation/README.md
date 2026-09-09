# Browser verification at 83f56d8

The no-mistakes test agent exercised the real `bin/dev` app (Puma and Solid Queue)
on port 3142 through Chromium. It used isolated development databases and a local
deterministic HTTP provider on port 18434. No external model calls were made.
The captain's development database and port 3000 were untouched.

Source: `83f56d82d54ac2965a0bab16d2e6dbb725abaf4d`. Recovery merge
`4b7235b73106eb1ac2cfdd7e341c42dff5e1dfa5` has the exact same Git tree
(`028541c22432f9452692a769a4f826cdf746b9ed`). These are engine and delivery checks;
a fake provider cannot demonstrate model realism.

The agent reported no findings after these checks, but run
`01M22V7RJHYRRPXHX04EJ2M0M0` exceeded its 30-minute test-stage limit before returning.
That pipeline failed on timeout and did not reach push or PR creation. Its completed
browser evidence is retained here independently of that pipeline outcome.

- [Persisted game state](persisted-state.txt): gifts, ceasefire, following/staying,
  rejected stale choices, crossing tolls, command outcomes and the cleared checkpoint.
- [Arrival prompt delivered](arrival-context-delivered.txt): current cast, carried
  items, wounds and the specific crossing toll.
- [Duplicate and overtaken delivery](duplicate-and-overtaken-delivery.txt): a resend
  bought no extra calls, and an old job wrote and broadcast nothing.
- [Provider call index](provider-call-index.txt): local fixture calls only.
- [Original evidence archive](original-browser-evidence.tar.gz): complete unmodified
  agent README, provider harness, request ledger, logs and screenshots. Extract it
  into a scratch directory to read the original reproduction instructions. Its
  transient worktree/database was removed after validation; recreating the fixtures
  is required before replaying those browser paths.

The readable text copies above have trailing whitespace removed. The archive
preserves the original files byte for byte.

Screenshots:

| Behavior | Actual page |
| --- | --- |
| NPC gives an owned key | [View](01-npc-gives-key.png) |
| Ceasefire ends the fight | [View](02-npc-ceasefire-ends-fight.png) |
| Follower arrives with player | [View](03-npc-follows-into-courtyard.png) |
| Malformed dialogue applies no effect | [View](04-malformed-dialogue-no-effect.png) |
| Toll visible despite silent prose | [View](05-toll-notice-visible-in-log.png) |
| Queued submission acknowledged | [View](06-queued-line-acknowledged.png) |
| Renderer outage uses factual arrival | [View](07-renderer-outage-factual-arrival.png) |
| Generation resumes from checkpoint | [View](08-generation-resumed-arrival.png) |
| No model configured, completed turn | [View](09-no-narrator-completed-turn.png) |
| No classifier, unfinished turn | [View](10-no-narrator-unfinished-turn.png) |
