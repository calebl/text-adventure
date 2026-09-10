# Rebaseline stale instruments

The captain authorized these sets as before sides for future prompt changes.
This work does not judge or edit a prompt. The main comparison crosses existing
request drift; the historical classifier sets measured older labelled cases.
All historical files are preserved byte for byte (`historical-identities.json`).

Offline capture and registry pricing precede paid work. `*-identity-before.json`
records the existing task outputs; `prices.json` runs the named estimators after
loading the registry into the isolated scratch database. `estimate.log` is the
whole-loop estimator, without a whole-loop purchase. Classifier's detailed
identity output adds separate system/user digests without changing its request
identity. Ending's after identity is a versioned scaffold identity.

`run.rb` invokes the existing rake tasks on one pinned arm. It disables transport
retries to bound unknown charges, preserves sampling parameters, and reserves
the model registry's full output allowance before each request. Failed or
unreported requests retain their reservation. The ledger includes warmups and
ending preludes. It separates registry-priced usage from optional provider
billing; streaming responses do not always report billing metadata. The raw
ledger's `registry_usage_usd` is the conservative accounting calculation (cache
usage is counted again at the full input price). It is not the provider bill.
`summarize.py` labels that value `registry_usage_upper_usd` and separately totals
RubyLLM's `registry_cost_usd` as `registry_priced_usd`, which accounts for cache
pricing. Per-set receipt summaries are written beside the kept results with
`summarize.py --write-kept`. An upstream
billing error cannot be undone by a local guard.

Re-price without buying:

```sh
DATABASE_URL=sqlite3:tmp/rebaseline.sqlite3 bundle exec rake ruby_llm:load_models
DATABASE_URL=sqlite3:tmp/rebaseline.sqlite3 bin/rails runner doc/evidence/ta-bench-rebaseline-stale/price.rb
```

Recompute task totals:

```sh
python3 doc/evidence/ta-bench-rebaseline-stale/summarize.py
```

The initial harness attempted a nonexistent Chat schema reader, producing only
local failures and no paid calls. `main-preflight-failure.log` preserves that
attempt. The corrected harness reads the existing RubyLLM chat schema. An early
concurrent digest attempt hit SQLite's writer lock; subsequent offline work uses
a separate scratch copy. Neither failure is a baseline.

The classifier's historical alternate models are not refreshed. The current
baseline order is fulfilled on the authorized pinned default model. Prose checks
remain bounded predicates, not a quality or outcome-fidelity judgment, and the
classifier's closed-set identity covers its designated staged position rather
than every runtime request.
