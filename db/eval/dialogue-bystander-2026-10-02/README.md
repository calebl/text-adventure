# Dialogue with a bystander, narrated

The same bench as `dialogue-bystander-2026-09-28`. Tobin stands beside Maren
and has spoken up unasked: he greets the player, tells them to leave, or demands
the coin purse they carry. The one thing that changed is the exchange
narrator's instructions, which now carry the owner's approved paragraph. It goes
straight after "Add nobody who is not listed above.":

> Tobin also spoke up unasked, as "What else happened here" above records.
> Narrate that too, as part of this exchange, in a sentence or two of its own.
> Nothing Tobin said changes what is recorded above.

The structure was frozen and the text was the only variable. Rebuilt with
today's engine, every row of the earlier set keeps a byte-identical character
request, and its narrator request differs by that paragraph alone. The paragraph
appears only when somebody other than the person addressed spoke up and has not
yet been told. So the main corpus's requests do not move
(`desires-dialogue-20260919` rebuilds with no mismatch) and it was not bought
again.

Three cases, four repetitions, both passes, on `mistralai/mistral-medium-3.1`:
24 calls, $0.012410. The provider billed each character pass at exactly the
registry's price; each narration is streamed and reports no bill, so it is
counted at the registry's price.

- `trial.json`: the trial, one repetition of the same three cases, 6 calls,
  $0.003209, read by hand before the full run. It is marked as a trial, and no
  comparison takes it.
- `aborted-budget.json`: a first attempt at the full run. It was stopped by its
  own spending watcher, which had counted an in-flight reservation as spent,
  while the first character pass was still in the air. That call has no receipt
  and recorded no row. At most it cost a full answer at the registry's rates,
  about $0.005.

The whole purchase was $0.0206 at most.

`rake eval:dialogue_compare BEFORE=dialogue-bystander-2026-09-28 AFTER=dialogue-bystander-2026-10-02`:

| metric | before (median) | after (median) | verdict |
| --- | --- | --- | --- |
| `bystander_named` | 0.0 | 1.0 | REAL (p=0.0286) |
| `state_failure` | 0.0 | 0.0 | noise |
| `exchange_failure` | 0.0 | 0.0 | noise |
| `narration_words` | 40.0 | 45.7 | noise (p=0.057, band 11.0) |
| `reaction_words` | 61.7 | 63.2 | noise |
| `contradiction` | unavailable (no human annotations) | | |

Read by hand, all 12 narrations:

| case | Tobin told | rendered wrongly |
| --- | --- | --- |
| greet | 4 of 4 greet the player | none |
| dismiss | 4 of 4 tell the player to leave; 3 add that nobody moved | none: nobody leaves |
| demand | 4 of 4 demand the coin purse; 4 say nothing came of it | none: the purse stays with the player |

Every one of the 12 tells Tobin in the same form: a closing sentence in the
past perfect ("Earlier, Tobin had spoken up unasked and greeted you."). It is
reported rather than heard, never quoted, and in two greetings set "as you
entered" or "as you arrived". That is consistent with the records, since his
row was written before the exchange was narrated. But it is told beside the
exchange rather than as part of it, which the paragraph asks for. How he
should sound is a prompt question this set leaves open.
