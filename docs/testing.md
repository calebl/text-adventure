# Comparing test runs

## The suite's assertion total is not a change detector

`bin/rails test` reports the same number of runs every time on the same code,
but its assertion total moves between identical runs. That is not flakiness and
not parallelism: several tests assert an invariant **once per thing found** in
generated data, and interiors, worlds and sweeps are laid out from seeded rolls
(`Roll`), so how many things there are to find differs from run to run while
the test passes identically every time.

The shape to recognise is a loop over what exists with a filter and an
assertion inside it. For example:

- `test/models/location/interior_test.rb` — "every stair joins two rooms that
  stand over each other" and the basement-stairs test assert once per staircase
  (`next unless row.travel_method == Location::Interior::STAIRS`).
- `test/lib/seeded_worlds_test.rb` — "every seeded mechanic has something it can
  actually do" asserts once per `shuffle_connections` mechanic.
- `test/lib/engine_sweep_physical_actions_test.rb` and
  `test/models/story/audit_precision_test.rb` work over generated rows too, and
  their assertion counts have been seen to move the same way.

The list is illustrative, not complete: any new test of that shape joins it.

**Do not rewrite these tests to have fixed assertion counts.** An invariant
asserted over everything that exists is stronger than three hand-picked cases;
the defect is in reading the total as a guard, not in the tests.

## The guard: a per-file, per-test comparison

For a rename, a rewording or any change that should leave the tests' meaning
alone, compare before and after **per test file**, not by the total:

1. Record, for each test file, its run count, its assertion count and the set of
   test names it discovers.
2. Run the base commit **twice** first, to show which files are deterministic
   and which move on their own.
3. Run the change and compare file by file. Run counts and test names must
   match exactly (or differ by exactly the tests the change added or removed).
   A moved assertion count is accounted for assertion by assertion — unless the
   file is one of the data-variable ones above, which is expected to move and is
   judged on its runs and names instead.
