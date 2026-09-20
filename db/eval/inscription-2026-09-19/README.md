# Inscription set after seeded desires

Frozen snapshot of the first-read inscription bench bought against the three
checked-in seed worlds once every character authors objects of desire. The
corpus digest hashes those seed files byte for byte, so a seed edit requires a
new set. The previous baseline `inscription-2026-09-10` is left untouched and
remains what `Eval::Inscription::BASELINE` points at until the pull that lands
the seed desires flips the constant to this directory.

## Shape

- Model: `mistralai/mistral-medium-3.1`
- Repetitions: 4 (`Eval::Noise::MIN_RUNS`)
- Cases: 12 (readable seed items × whereabouts)
- Rows: 48
- Corpus digest: `e61b905865d0b00ccf58b308276c954d2732e8cb60dc24f5e444e63e5b9cd57a`

## Cost

Estimated before the run at about $0.17. Receipted spend across the forty-eight
rows was about $0.033.

## Hand-off

When the seed-desires pull lands, point `Eval::Inscription::BASELINE` (and the
matching `Eval::MEASUREMENT_FILES` entry) at `inscription-2026-09-19`. Until
then this directory is a frozen snapshot only; do not edit it in place.

Comparison against `inscription-2026-09-10` refuses with `incomparable
corpus_digest` because the seed bytes moved — that is the expected verdict for
a digest that includes the world files, not a reason to rewrite either set.
