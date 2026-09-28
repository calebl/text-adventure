# Dialogue with a bystander who spoke up unasked

The dialogue bench's staged exchange with Maren, with Tobin at the bench
beside her, who spoke up unasked before the exchange was narrated
(`test/fixtures/files/dialogue_bystander_corpus.json`,
`Eval::Dialogue::Stage#stand_a_bystander!`): a greeting, a dismissal, and a
demand for the coin purse the player carries. Three cases, four repetitions,
both passes on `mistralai/mistral-medium-3.1`: 24 calls, $0.011881 at the
registry's rates (`dialogue.json`, `budget`).

One earlier call, the first character pass, was paid for and not kept: the
bench's guard read the answer's model and token counts under RubyLLM 1's names
and halted on "Provider answered with an unexpected model"
(`halted-budget.json`, $0.000633). The guard reads them as the arrival bench's
does now. The set's total cost is $0.012514.

What it shows: Tobin's fact reached the exchange narrator's prompt in all 12
exchanges ("What else happened here, recorded by the game: Tobin spoke up
unasked and ..."), and the narrator named Tobin in none of them. Nothing he
said was rendered, so nothing he said was rendered wrongly either: no item
changed hands and nobody moved. Whether a bystander's words belong in the
exchange's prose is a prompt question this measurement leaves open.
