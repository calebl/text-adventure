# Typed volition decision: first baseline, 12 staged rooms x 4 repetitions

`rake eval:volition_baseline SET=volition-baseline-20260926` sent each of the
twelve staged rooms in `requests.json` to OpenRouter Decisions
(`typesafe/jev-1.13`) four times, under a 0.05 USD ceiling that stops rather
than exceeds. All 48 calls answered 200.

`requests.json` is a copy of `test/fixtures/files/volition_baseline_requests.json`
as it was sent. `Playthrough::Volition::BaselineRoomsTest` builds those rooms
offline from the seeded worlds' own people and rooms and pins the file against
`Playthrough::Volition::SystemOne#request`, so the questions and the pressure
criteria are the app's constants in every room and only the staged state
differs. `receipts.json` keeps every receipt: response id, `usage` with
`usage.cost`, and the answers.

`rake eval:volition_baseline_summary SET=volition-baseline-20260926` prints the
full per-room summary from these two files for free;
`Eval::VolitionBaselineTest` pins the headline figures below.

## Cost

- 48 calls, 0.001683864 USD by the receipts' `usage.cost`; 0.000035080 per call.
  Two-person rooms cost about 0.00005 a call, one-person rooms about 0.00003.
- The credit bracket around the run rose 0.006878 USD. The account is shared,
  so that rise cannot be attributed to this run; the receipts are the figure.

## What it shows

- **Repetitions agree.** 13 of 14 people chose the same act on all four
  repetitions (mean agreement 96%). Pressure scores vary by about 0.01 between
  repetitions. The one split: Perrin Lasco, in Ward Office 12 with Halkett Rowe,
  gave the player his private index twice and stayed put twice.
- **Staying put dominates.** Of 56 answers, 38 were "Stay where you are", 8
  a walk out, 8 picking something up, 2 a give, and none chose to follow the
  player or to stop following.
- **Serves is spread across all five answers**: recognized 16, unrecognized
  12, none 12, conscious 8, unconscious 8. Each person's serves answer was the
  same on every repetition.
- **Pressure sits in a narrow band, mostly just over the line.** Mean 0.630,
  range 0.44 to 0.85. It was at or over 0.5 in 48 of 56 answers, so the typed
  act would replace the die for nearly everybody. Only two rooms stayed under:
  Grenn Ollivar with the rent envelope lying there (about 0.45) and Perrin
  Lasco following the player in the supply closet (about 0.48).

## What looks wrong

- **Twelve answers say the act serves nothing** (Ammon Brace alone in the
  Causeway Court, Neb Halloran alone at the Tide Post, and Perrin Lasco walking
  out of the supply closet), and in every one of them the pressure was over
  0.5, so an act the reader says serves no desire or need would still replace
  the die. That may want the overlay to read `serves` as well as pressure.
- **Pressure barely separates rooms.** Several rooms with nothing pressing
  score just over 0.5 (Grenn alone in Room 3 at 0.52, Ammon alone in the court
  at 0.52), so the 0.5 threshold is deciding on a margin smaller than the gap
  between rooms. Whether the pressure question or the threshold should move is
  a follow-up that needs its own measured before and after.
- **Waiting wins even where the pursuit is active.** Neb Halloran (obtain) was
  handed the deed to his mother's roof and a player asking who paid for it, and
  stayed put with pressure 0.82. The die weights waiting low for an active
  pursuit; the typed act, which replaces the die at this pressure, mostly waits.

No prompt or criteria change was made for any of these.
