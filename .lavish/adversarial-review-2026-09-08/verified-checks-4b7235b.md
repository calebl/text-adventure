# Recovered source verification

Source: `4b7235b73106eb1ac2cfdd7e341c42dff5e1dfa5`, whose Git tree is exactly
`83f56d82d54ac2965a0bab16d2e6dbb725abaf4d` (the final reviewed source).
Only report/evidence files were added after this source verification.

- `bin/rails test`: **4,154 runs, 23,400 assertions, zero failures, errors or skips**.
  [Raw output](verified-suite-4b7235b.log). Includes engine sweeps. Executed with
  `RAILS_ENV=test`, an isolated `/tmp/ta-final-validation-ffcl041t/test.sqlite3`
  `DATABASE_URL`, an empty provider key and `TA_LOCAL_MODELS` unset. The Rails test
  helper also removes the provider key/configuration. No paid calls.
- `bundle exec rubocop`: **556 files inspected, no offenses**. Cache redirected to
  `/tmp/ta-final-validation-ffcl041t/rubocop-cache` because the sandbox cannot write
  the user's default cache.
- `RAILS_ENV=test bin/rails zeitwerk:check`: **All is good!**
- Report regenerated from `verification.json`; original findings and measurement
  artifacts were preserved. All generated HTML evidence links resolve locally.

The first restricted test launch could not open Rails' local parallel-worker IPC
socket. An authorized launch outside that restriction ran the suite but found one
invocation error: explicitly setting `TA_LOCAL_MODELS=0` violates the classifier
bench's assertion that the default opt-in variable is absent. Removing that override
produced the clean full-suite result above; no application or test code changed.

The earlier no-mistakes run completed review and browser checks but failed on a
30-minute test-stage timeout before returning. It never pushed. Its commits were
preserved and recovered through the tool's archive/custody workflow; the recovery
merge retains both histories and exactly reproduces the reviewed tree. The new
PR delivery run, and GitHub's checks on its published head, remain separate results.
