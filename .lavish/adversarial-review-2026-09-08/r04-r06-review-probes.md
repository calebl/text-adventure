# Review probes for R04/R05 and R06

Three offline probes written during review of this branch, archived with the runs
they actually produced. **No probe here makes a provider call**: every one stands
`BaseAgent` in with a queued fake, and two of them fail the run if a provider is
reached at all.

Each log below is the raw stdout of the run named beside it, kept byte for byte.
The first lines of the Ruby logs are the environment's own warnings (a read-only
`$HOME` for bundler, `io_uring`, an unwritable `log/test.log`, the missing
`image_processing` gem). They belong to the machine those runs happened on and
say nothing about any commit.

The scratch SQLite databases and the `game-locks/` directories beside them are
deliberately NOT archived — they are rebuilt by the rerun instructions.

## Rerun any of them

Every probe needs an isolated database of its own. Build one from **this
checkout's `db/schema.rb`** in `/tmp`; never point one at the development
database, and never at a scratch database from an earlier run.

```bash
export RAILS_ENV=test
export DATABASE_URL="sqlite3:/tmp/ta-review-probe-$(date +%s)/probe.sqlite3"
mkdir -p "$(dirname "${DATABASE_URL#sqlite3:}")"
bin/rails db:schema:load                     # db/schema.rb, into that file only

bin/rails runner .lavish/adversarial-review-2026-09-08/r06-sequential-exit-probe.rb
bin/rails runner .lavish/adversarial-review-2026-09-08/r06-provisional-receipt-probe.rb
```

`GameLock` writes its lock files into a `game-locks/` directory beside whichever
database is configured, so an isolated database keeps its locks isolated too.

The observer probe configures its own database instead — a fresh
`/tmp/gate6-observer-drain-<random>.sqlite3` loaded from `db/schema.rb` — so it
is run directly and needs no `DATABASE_URL`:

```bash
ruby .lavish/adversarial-review-2026-09-08/r04-r05-observer-drain-probe.rb
```

It exits non-zero if any check fails or if the three files it hashes change
under it mid-run.

## Sequential exit admission (R06)

`r06-sequential-exit-probe.rb` stages ten stub realizations, each with a fixed
detail answer and one fixed exits answer, and records for every case what
`Location::Generator#realize!` did: the error class, the detail level, the
checkpoint phase, whether an exits answer stayed cached, and the exits actually
written. It then replays the writer's own two loops over the same proposals, with
no preflight, to show what those attributes really require.

- Before, on a clean `262e8c559f909a255d8f7cfa02ed648f2f5e1199`:
  [r06-sequential-exit-before.log](r06-sequential-exit-before.log).
  **Four of the ten cases are the defect** — `already_has_exit`,
  `complete_existing_pair`, `duplicate_new_alias` and `capacity_reached` each
  raise `ActiveRecord::RecordInvalid` and stay `stub`/`exits_pending` with no
  cached exits, while the writer loops beside them accept the same answer
  (`writer_error: null`). **The other six are controls** — `natural_key_self`,
  `forced_valid`, `half_pair_valid` and `far_end_full` realize;
  `forced_invalid` and `half_pair_invalid` are labels the writer really does
  use, and are refused.
- After, on the committed `e14124d128e691904a93c3e3b61c18491dc8bd09`
  (`app/models/location/generator.rb` SHA256
  `256ca3d1f601f6b304a8479393dbb9dc77efe8feeeb167c921bcc76d90900f8d`):
  [r06-sequential-exit-after.log](r06-sequential-exit-after.log). All four
  failures now realize with exactly the writer's own exits, and all six controls
  keep the outcome they had — the two genuine refusals still raise, now as
  `Location::Generator::UnusableExitLabel`, still leaving `exits_pending` with
  `cached_exits: false`.

## Provisional exits receipt (R06)

`r06-provisional-receipt-probe.rb` interrupts a realization after the exits
answer has been stored and before the graph is written, three ways: a worker that
dies with a valid answer stored, one that dies with an unusable label stored, and
an edge save that fails with `ActiveRecord::StatementInvalid`. Each scenario then
retries through a FRESH `Location::Generator`, with `BaseAgent` stubbed to raise
if it is touched. The probe asserts rather than prints: it raises if a receipt is
lost, if a partial graph survives, if a retry pays for detail again, or if the
finished room does not end with exactly one two-row door.

- After, on the same committed `e14124d`:
  [r06-provisional-receipt-after.log](r06-provisional-receipt-after.log). The
  valid receipt and the persistence failure are retried with no model call at all
  (`exit_calls_on_retry: 0`); the unusable one is refused, its exits slice
  dropped while the paid detail survives, and the corrected answer costs one
  exits call and no detail call (`exit_calls_on_retry: 1`). Every scenario ends
  with `provider_calls: 0`.

## Observer isolation and the drain (R04/R05)

`r04-r05-observer-drain-probe.rb` queues two accepted commands and plays them
through `Playthrough::Turn#play` five times over, failing a different consumer
each time: none, the first `on_start`, the first `on_finish`, the engine itself,
and the `on_error` consumer. It records the submission statuses, the resolved
actions, the scenes written, what the party ended up holding and what the caller
was handed, and for the healthy runs it then redelivers both tokens to check that
the newest submission still replays and the overtaken one still says nothing. It
hashes `turn.rb`, `command.rb` and `narration_job.rb` before loading them, after
loading them and after the trials, and fails if any of the three moved.

- Before: [r04-r05-observer-drain-before.json](r04-r05-observer-drain-before.json),
  recorded on a clean `262e8c5` (`turn.rb` SHA256 `d3909c21…`). Three checks
  fail: a failed start observer leaves `["failed", "pending"]` — the line was
  never played and its token can no longer be retried — a failed finish observer
  leaves the second line `pending`, and a failed error observer replaces the
  engine's own exception with the consumer's.
- After: [r04-r05-observer-drain-after.json](r04-r05-observer-drain-after.json).
  All eight checks pass. **This run was made against an uncommitted patch**, and
  the JSON says so in its own words: its `head` is still `262e8c5` and its
  `dirty` list carries `M app/models/playthrough/turn.rb`. It is archived
  unrelabelled. What ties it to this branch is the hash it recorded for the file
  it exercised — `turn.rb` SHA256
  `d04c3d51e54a5a23f962cc7a2c8adb7fcc57ebb3311b1d8ba612f276af51a8fa` — which is
  `app/models/playthrough/turn.rb` at the committed `e14124d`, byte for byte
  (`git show e14124d:app/models/playthrough/turn.rb | sha256sum`). Later commits
  on this branch change that file's comments, so the hash identifies `e14124d`
  and not the head of the branch.

The committed regressions for the same boundary run the real `NarrationJob` with
a real broadcast failure (`test/models/playthrough/drained_turn_test.rb`), and
the player loop is covered by the R04/R05 sweep scripts; this probe is the
independent read of the same behaviour, not a substitute for either.
