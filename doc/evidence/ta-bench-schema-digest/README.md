# Request identity evidence

The starting revision is the scout's audited main. `digests.log` recomputes
legacy and added identities from this checkout; `ending-digest.log` uses a
fixed synthetic prelude and is not evidence of live ending prompt equality.
`spend.json` records the estimate and actual spend. No provider requests or
registry pricing requests were needed.

Reproduce from the isolated worktree (its own test database):

```sh
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test OPENROUTER_API_KEY= TA_LOCAL_MODELS=0 bin/rails eval:prompt_digest eval:classifier_digest eval:realization_digest
RAILS_ENV=test OPENROUTER_API_KEY= TA_LOCAL_MODELS=0 CORPUS=ending bin/rails eval:prompt_digest
RAILS_ENV=test bin/rails eval:manifest
bin/rails test
bundle exec rubocop
bin/rails zeitwerk:check
bin/brakeman --no-pager
```

The validation logs retain the command output. The full Rails log includes
existing rake constant redefinition warnings from task-loading tests; its final
summary records the result. The manifest freezes the new identity builders and
the existing measurement code. No file in `db/eval/`, gameplay prompt, schema,
seed, migration, or engine implementation was edited.

`request_identity` is additive and versioned. Its schema serialization follows
`RubyLLM::Chat#with_schema` in the installed gem: instantiate the schema class,
then call `to_json_schema`. Canonicalization sorts object keys while preserving
array order and values. This detects schema-only edits without changing legacy
message identities.

Normalization happens before rendering. Realization fixes slot data and renders
the engine's supported counts, retaining count-dependent wording and schema
variants. Classifier names and list sizes come from its fixed designated corpus
position; no database identifiers or random population draws reach its prompt.
These seed-owned labels remain hashed so a changed closed set is detectable.
The legacy realization scrub is deliberately retained for compatibility; the
new identity does not use its whole-line deletions.

Generated assistant detail replayed before exits, variable ending preludes,
and undesignated branches are outside this scaffold identity. It detects input
changes, not quality regressions in unscored behavior. Historical schemas were
not recorded and cannot be retroactively baselined. Existing sets remain valid
before sides; the separate re-baselining task must buy any new schema baseline.
