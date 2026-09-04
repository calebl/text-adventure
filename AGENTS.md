# AGENTS.md

Guidance for AI coding agents working in this repository.

## Start here

**[ROADMAP.md](ROADMAP.md) is the source of truth for status and tasks.** Read it
before planning any work. It records what is built, what is next, the reasoning
behind the persistence model, and the known issues.

When you finish a piece of work, update `ROADMAP.md` in the same change: check
off what landed, move it into **Status → Done**, and add anything new you
discovered to **Next up** or **Known issues**. A task queue that drifts from the
code is worse than none.

`CLAUDE.md` holds the project conventions (testing requirements, factory rules,
architecture notes). This file and `CLAUDE.md` are complementary — conventions
there, status here.

## What this project is

A text adventure that generates itself as the player explores, and keeps what it
generates. `Location` is the durable world and is generated once; `Scene` is a
timestamped moment in a location. See the persistence model section in
`ROADMAP.md` before touching either model — that split is the whole design.

## Working agreements

### The standing constraint

**Nothing may depend on the narrator obeying its prompt.** Prompt it with the
world's rules — that is cheap and it raises the odds — but never let a
guarantee rest on its compliance. *Gate the state, inform the prose, audit the
difference.* Where a model must be involved, do not ask it what should happen:
ask it to pick from a set the app closed, then have the app act on the record,
never on the label. The README's turn diagram states it in colours
([README.md](README.md#how-a-turn-works)); `ROADMAP.md` → *The standing
constraint* has the captain's wording and where the full audit lives.

### Talking to models

- All LLM calls go through `BaseAgent` (`app/agents/BaseAgent.rb`). It handles
  model selection and rotates to the next model when a call fails. Do not build
  a bare `RubyLLM::Chat` in new code.
- **A 401 does not rotate.** `RubyLLM::UnauthorizedError` is re-raised as
  `BaseAgent::UnauthorizedProviderError` instead, because a rejected key is
  fixed by a key and not by a different model — and the local ollama models are
  at the bottom of the same list, so rotating past a 401 answers from a 4k CPU
  model with nothing saying the remote call was refused. Keep any new failure
  class on the same side of that line: rotate on "this model failed", raise on
  "our setup is wrong".
- **A REFUSAL IS A FAILED CALL, and there are now three sides to that line, not
  two.** An unschema'd response that declines the prompt — or answers it with a
  menu of alternatives — raises `BaseAgent::RefusalError` and **rotates**, which
  is the whole point: measured over 51 charged narrator prompts,
  `minimax/minimax-m3` refused 8 and `mistralai/mistral-medium-3.1` refused none
  of them, so the app already had the model it needed and could not reach it. A
  refusal is a 200 OK. That same measurement later put mistral **first** in
  `REMOTE_MODEL_IDS`, so this rotation now falls to minimax rather than to a
  model known to comply — read the note on the constant before relying on it. `BaseAgent::Refusal` carries the rule; it is STRUCTURAL
  (an unquoted first-person opening, or a list) and not a word list, because a
  word list both misses the refusals that matter and fires on every character
  who says "I". Do not widen it into one — `BaseAgent::RefusalPrecisionTest`
  pins the measurement on 127 real responses and will fail.
- **A CRISIS RESPONSE IS THE THIRD SIDE, and it does not rotate.** When a model
  answers with a real-world crisis line, `BaseAgent::CrisisResponseError` is
  raised and re-raised without rotating. Rotating would land on a model that
  narrates the same exchange in fiction, which is the app quietly routing around
  a safety response — a decision somebody has to make on purpose. It was made:
  suppress the model's version so it is never a `Scene`, and show an
  app-authored message outside the fiction (`Playthrough::SafetyNotice`,
  rendered by `NarrationJob`). **The two checks are ordered, not merged**, and
  crisis is checked first because one response can be both. Keep them apart.
- **A TRUNCATED FIELD IS A FAILED CALL TOO, and it rotates.** A generated field
  that arrived at exactly the `max_length` its schema asked it to stay under was
  cut off by the provider, and `SanitizesGeneratedText::TruncatedTextError` is
  what says so. It is on the `SchemaIgnoredError` side of the line — the model
  did not deliver the shape it was asked for — so it must raise where the
  rotation can see it. **The check stays with the caller and only the raise goes
  inside the loop**: caps belong to the schema and the sanitizing concern, not
  to `BaseAgent`, so `BaseAgent#ask` takes a `verify:` callable and runs it on
  the parsed content inside the attempt loop. `InteractionAgent#ask` is the one
  caller. Do not move the check itself into `BaseAgent`, and do not call a
  sanitizer on a response `#ask` has already returned — that is the bug this
  seam exists for: the raise landed outside the rotation, so on plain minimax
  15 of 16 attempted narrations died and 1 of 18 talk turns completed
  (`data/ta-conversation-read/report.md` §4).
- **Neither check reads a schema'd response.** A character's five
  `Interaction::Schema` fields are first-person by nature — "I should probably
  answer" is what a `pre_thought` IS — so reading them for a first-person "I"
  would fail every talk turn in the game. A schema'd response that came back as
  prose is already caught by `verify_schema_honored!`.
- **A FAILED TURN IS NOT SHOWN THE EXCEPTION.** `NarrationJob`'s general rescue
  renders `Playthrough::TurnFailureNotice` — app-authored copy, one line — and
  logs the real error at full detail. Every reason a turn fails is internal (a
  model that would not answer, a schema it ignored, a sheet cut off at its cap),
  and `finish(error: e.message)` used to put an internal cap and a fragment of
  suppressed model output in front of a player. Keep new failure classes on that
  side: log the reason, show the notice. It is a `.alert` above the log and
  deliberately not shaped like `Playthrough::SafetyNotice`, which is an
  interception rather than a failure.
- **A response the game will not keep is not persisted.** `Scene::Narrator`'s
  `ensure` saves whatever arrived, which is right for a call that died
  mid-sentence and wrong for a refusal, so `BaseAgent::UnusableResponseError` is
  its one exception. It also keeps the **last attempt's** content rather than the
  streamed buffer: `#ask` restarts the stream when it rotates, so the buffer
  holds a refusal and its replacement end to end.
- **THE PROSE IS TOLD THE MOMENT, FROM THE RECORDS, AND ONE BUILDER TELLS
  IT.** `Playthrough::Moment#narration_context` is what `Scene::Narrator` and
  `InteractionAgent`'s narrator pass both read: the story, the room, **the ways
  out, who else is here and what the player carries**, then the last turn and
  the recap. Those three lists are the closed sets `Playthrough::Classifier`
  already computes every turn and used to throw away once the intent resolved;
  the narrator's instructions had always said not to invent an exit "the player
  has not been told about" without anything telling it which exits those were.
  Stated even when empty — "carrying: nothing" is a fact, silence is an
  invitation. This is the cheap half of the standing constraint done with facts
  rather than rules; it does not make the narrator obey, and `Playthrough::Drift`
  is what says whether it helped. Add a fact to the `Moment`, not to a caller.
- **A REACH THAT RESOLVED TO NOTHING IS REFUSED, NOT NARRATED**, on the ruling
  of 2026-09-04. It used to be stated to the narrator as a fact through the same
  `fact:` seam `take` and `drop` use (`Playthrough::Turn#reach_fact`, now gone):
  before *that* the narrator got the bare command, walked the player through the
  door anyway, and the next arrival contradicted it. Refusing writes nothing at
  all, which also retires that branch's one known cost — a classifier miss on a
  real exit read as prose denying a door that is there. `take` and `drop` still
  use `fact:` for what they DID, so the seam is live; only the reach case left
  it. `examine` goes along as an intent label (`Scene::Narrator::DOING`) so a
  look is narrated as a look. Everything else is still the bare command.
- **THE CHARACTER IS TOLD THE MOMENT TOO, in the per-turn message and not the
  sheet.** `Playthrough::Moment#character_context` gives the character pass the
  room's *name*, the story hour, who else is standing there, **what the player
  typed on the last turn, quoted from `scenes.typed`**, and what it already
  concluded on the exchanges the chat no
  longer replays** — `Interaction#inner_resolution`, read back at last, under
  `Moment::CONCLUSIONS_BUDGET`, skipping the `Chat::HISTORY_EXCHANGES` the chat
  sends verbatim. It goes in the user turn so a replayed exchange keeps the room
  it happened in. And the user turn names the protagonist: it used to read
  "The user input is", undoing `#addressee_section` every turn, and so did every
  `Interaction::Schema` description. Nothing in a talk prompt says "user" now;
  `InteractionAgentTest` pins it.
- **A CHARACTER PROMPT CARRIES RECORDS ONLY, never prose a model wrote.**
  Stricter than `#narration_context`, and it has to be: the narrator writes to
  the player, so last turn's prose can be handed to it as it stands, but the
  same sentence read by somebody else in the room is an assertion about *them*.
  `Scene.recap_line` was replayed into `#character_context` and every shape of
  it was in the wrong register — a scene summary is engine-facing third person,
  a talk turn's says "The player spoke with" the very character reading it, and
  a narrated turn has no summary at all so the fallback is the narrator's
  **second** person, where every other "you" in that prompt means the character.
  Measured: the character then performs the player's physical action as its own
  6 times in 10 against 0 in 10 (Fisher exact p = 0.011). It quotes
  `scenes.typed` instead (`Moment#last_attempt`), and `#conclusions` falls back
  to `Interaction#action` rather than the engine-composed `#summary` for the
  same reason. `Playthrough::MomentTest` pins both shapes.
- **A character's voice is one register per field, and
  `Character#interaction_instructions` names them by field.** The thought and
  resolution fields are first person; the feeling fields are two or three words;
  `action` is the one field anybody can see, and inside it speech is quoted and
  first person while the rest is the character named and pronouned from outside.
  The rule used to say everything outside the quotes is described from outside,
  which pushed the four thought and feeling fields into the third person the
  narrator's own example contradicts. `Character#pronoun_forms` is the table for
  a prompt that has to *build a sentence* — `"her eyes"`, `"they say"` — where
  `#pronouns` is the string to *state*; the interaction narrator's worked example
  is built from it, in the character's own name and pronouns, because a fixed
  example with "her" and "The person" was a nudge on every character who was not
  a woman.
- **Sampling is the provider's default everywhere except a closed-set pick.**
  `BaseAgent#with_temperature` exists for `Playthrough::Classifier`, which asks
  at `0.0`: one word from a fixed table and one name from a closed enum, where
  the same line typed twice in the same room resolving two ways is noise in the
  drift counter. Prose keeps the default. Setting it on the character pass is a
  measurement to make, not a default to assume.
- The scoping above has a history worth keeping: inside the quotes the
  character talks, so it says "I"; outside them it is described from outside,
  so it is named and takes its pronouns. The rule used to read "Refer to yourself in third person only" with
  no scope at all, two lines under the sentence establishing that quoted text is
  speech — so a character talking aloud said *"forgive Halkett, the name eludes
  him at present"*. Keep any new voice instruction scoped to a register.
- **AN NPC IS TOLD WHO IT IS TALKING TO, AND ONLY WHAT MEETING THEM WOULD TELL
  IT.** `Character#addressee_section` passes the protagonist's name, apparent
  age, race, appearance and pronouns and deliberately withholds `backstory`,
  `personality`, `likes`, `dislikes` and `fears` — those are the player's
  interior, and a prompt that shipped them would hand every stranger in the
  world what frightens the player before the player had spoken. `CharacterTest`
  pins the exclusion. What a character actually knows beyond sight arrives
  through `Chat.conversation_with`'s replay, not through the sheet.
- All LLM calls use structured output via `RubyLLM::Schema`. Schemas live
  alongside the model they populate (`app/models/universe/physical_schema.rb`),
  and are usually a declared class. `Playthrough::IntentSchema` is a factory
  instead, because its `target` is an enum over the exits and people in front
  of the player, which is only known per turn.
- **One documented exception, and the line is what the call PRODUCES, not which
  class makes it: prose the player watches arrive streams and stays
  unschema'd; anything that fills a record stays schema'd.** Structured output
  and token streaming are mutually exclusive here — with a schema attached the
  model emits JSON, so a player watching the stream sees
  `{\n  "description": "The doorway...` arrive a character at a time (and the
  call runs ~4x longer). Two calls are on the prose side of that line, and only
  two: `Scene::Narrator`, which answers what the player *typed*, and
  `InteractionAgent`'s second pass, which turns a character's reaction into
  prose. Note the shape of the second one — the same turn's *structured* half
  (`Interaction::Schema`, five fields) is a separate schema'd call, so nothing
  a record needs is left to prose. Do not "fix" either by giving it a schema,
  and do not add a third without that same split.
  **`Scene::Generator` is `Scene::Narrator`'s sibling, not a second copy of
  it.** It narrates walking *into* a place, which is a record rather than a
  turn, so it is schema'd like everything else and returns a `Scene` instead of
  streaming. If you find yourself giving one of them the other's job, the two
  classes have drifted — today the line is "answering a command" versus
  "writing a moment". A refactor to split them by *facts* versus *story*
  instead is filed as its own work item; until it lands, keep the current line.
- **Never let `ruby_llm-schema` resolve to 1.x.** Its 1.0.0 is a deprecation
  shim forwarding to the renamed `schematist` gem. `ruby_llm` itself still
  depends on `ruby_llm-schema ~> 0` and contains no reference to `schematist`,
  so its own constraint already rules the shim out — the `~> 0.2` in the
  `Gemfile` is belt-and-braces, not the thing doing the work. What matters is
  never *widening* past it: an unconstrained `gem "ruby_llm-schema"` lets the
  resolver take 1.0.0 and silently drags `ruby_llm` back to 1.8.2, the last
  release with no such dependency. That failure is silent twice over, because
  the shim and `ruby_llm` then disagree about what `to_json_schema` returns and
  `RubyLLM::Chat#with_schema` drops the schema with no error at all — every
  structured call goes out as prose.
  `test/models/ruby_llm_schema_envelope_test.rb` guards that seam all the way
  to the rendered request body; keep it passing.
  **Dependabot proposes the widening every week** — PR #91 rewrote the bound to
  `~> 1.0` and rolled the lockfile back to `ruby_llm (1.8.2)`, and the next one
  will look the same. Close it; the argument is here. Do **not** silence it with
  an `ignore` entry in `.github/dependabot.yml`: GitHub marks `ignore` as one of
  the options that also change how Dependabot raises pull requests for
  *security* updates, with no documented carve-out for its `update-types`, so
  the rule would quietly mute any future advisory on this gem whose fix is a
  major release. The rule is written out, commented, in `dependabot.yml` with
  that trade recorded. What keeps a 1.x from landing is CI rather than config:
  #91's `test` job went red with 11 failures and 6 errors.
- The explicit `Gemfile` entry stays even though `ruby_llm` would pull the gem
  in anyway: every schema class here subclasses `RubyLLM::Schema` directly, so
  it is a direct dependency. If `ruby_llm` 2.0 does switch to `schematist`, an implicit
  dependency would vanish and surface as a `NameError` rather than a
  resolution failure.
- **Never swallow a generation failure.** Generators raise. A rescue that
  returns a half-built record turns a missing model or a bad API key into
  "the AI gave me garbage," which is very hard to debug — this has already
  happened once in this codebase.
- **Verify a model supports structured outputs before adding it to
  `BaseAgent`.** Several OpenRouter `:free` endpoints accept a schema and answer
  in prose instead, which corrupts records silently rather than failing. Check
  with `curl -s https://openrouter.ai/api/v1/models | jq '.data[] | select(.id == "MODEL") | .supported_parameters'`
  and confirm `structured_outputs` is listed.
- Ask for a handful of fields per call, not twenty. Split large records across
  sequential calls on one agent, the way `Universe::Generator` does; the
  conversation carries context between calls. **A pass earns its round trip when
  its output is large enough to constrain the next one.** The universe's first
  pass produces ~584 tokens the second is told to stay consistent with, so it
  earns it. Two splits that did not — naming the opening location, and a
  character's identity before their background — produced 39 and 21 output
  tokens against ~2,300-token prompts, and were collapsed into the calls that
  already had the context.
- **Send each prompt only the context it can use.** `Universe#prompt_details`
  takes an audience (`:full`, `:character`, `:place`, `:dialogue`, `:scene`)
  because the whole record is 1,584 tokens and goes out again on every room and
  every turn of dialogue. Add a field to `Universe::AUDIENCE_FIELDS`, not to a
  caller. Before adding an audience, check that the prompt does not already
  carry the same facts in a more specific form: `:scene` is `:place` minus
  everything the location's own description and lore already say, which is what
  makes it 285 tokens instead of 628, and `:dialogue` takes race *names* only
  because the character sheet below it already carries the speaker's own race
  in full — which took it from 930 tokens to 606.
- **Every generated string goes through `sanitize_string`**
  (`SanitizesGeneratedText`). It is the one seam every model-written value
  crosses, so guards against model output belong there and not beside the field
  that first showed the problem — it strips emoji, and it strips the JSON
  envelope debris (`…”}`) a response cut at a `max_length` boundary leaves
  inside the value. Pass `max_length:` and it also **raises** when the value
  arrived at that cap, because a value at exactly its cap was cut off rather
  than finished. That reading is only safe while the cap is real headroom over
  the shape the description asks for, so the two go together: see
  `Interaction::Schema`, where the caps are the requested shape doubled and each
  description states its own budget. A field the guard rejects fails the turn
  rather than being trimmed — a fragment is not a shorter answer, it is an
  answer whose end is missing.
- **Sanitize where the consumers meet, not at each one.**
  `InteractionAgent#reaction_fields` builds both the narrator prompt and the
  `Interaction` row, so sanitizing there is what makes them agree. Checking the
  record alone would still have let a fragment shape the prose — and the
  narrator's whole job is to write fluently over whatever it is handed, which is
  why a bad field has to be caught before that pass runs.
- **`minimax/minimax-m3` writes its plan into the first string field it is
  given, and prompt wording does not stop it.** Measured over 30 real character
  passes per arm: `pre_thought` came back at exactly its 320-cap on 26 of 30,
  every one of them a stage note ("*I need to respond as Halkett Rowe… Let me
  think about this in character*"). Rewording
  `Character#interaction_instructions` moved that to 23 of 30 — i.e. not at all
  — while `mistralai/mistral-medium-3.1` and `google/gemini-2.5-flash` overrun
  0 of 180 fields on the same prompts. So the rate is the model's, not the
  prompt's; what the truncation *costs* is the `verify:` seam's business (see
  the truncation bullet above, and #92). Do not reach for prompt wording to
  reduce it; that was measured and it does not work.
- **Prefer a fixed table to a prompt** where the value is one of a known set.
  `LocationConnection::DISTANCES` and `::TRAVEL_METHODS` are enums the schema
  reads directly, and `time_to_travel` is derived from them rather than asked
  for. Free prose in a small `max_length` box truncates mid-word, and a
  directional phrase is wrong on the way back.
- Seed prompts with randomized "predetermined details" so repeated runs diverge
  (`Universe::Generator::TONES`, `Character::Generator::BIRTH_PLACES`).

### Conversations are kept, and bounded

Every `BaseAgent` writes a `Chat` and its `Message`s: the prompt, the answer,
the token counts and the model that actually replied. It is lazy — an agent
nobody asks anything leaves no row — and the granularity is **one chat per
agent conversation**, because a chat's messages have to be a list you could
send again: one system instruction, one schema, one model.

- **Which turn a message belongs to is on the MESSAGE** (`messages.scene_id`),
  not on the chat, because a durable conversation spans many turns. Whoever
  creates the `Scene` calls `BaseAgent#attribute_to!`; without it a turn's cost
  cannot be totalled and the debug view shows the turn as unrecorded.
- **A failed attempt is rolled back before the retry.** RubyLLM persists the
  prompt before it sends it, so without the rewind a rotation re-asks on top of
  the failed attempt and hands the replacement model the rejected answer. If you
  add a failure path to `#ask`, rewind on it.
- **`messages.content_raw` is load-bearing.** A schema'd answer is a Hash, and
  RubyLLM stores it there with `content` left nil. Drop the column and every
  schema'd call in this app persists an empty assistant message.
- **One conversation is picked up again rather than started fresh**: talking to
  somebody, keyed `(playthrough, character)` by `Chat.conversation_with`. It is
  the only one where last turn's words are worth replaying, and it is bounded by
  `Chat::HISTORY_EXCHANGES` because `Character#interaction_instructions` inlines
  the whole universe (4,705 characters on the seeded worlds) and the local
  models run in a 4,096-token window. Trimming means **deleting**: `Chat#to_llm`
  rebuilds the request from every persisted message, so history you keep is
  history you send. Nothing is lost — every exchange is an `Interaction` row.
- **The audit trail is kept, and that is a measured decision** (`Chat::KEEP_TURNS`,
  `Playthrough#prune_conversations!`, still called at the end of every turn).
  `KEEP_TURNS` is **nil unless `TA_CHAT_KEEP_TURNS` is set**, and nil prunes
  nothing. It used to default to 25 on the reasoning that this is a SQLite file
  on a laptop and the game reads none of it back — true in every clause, and
  measured it does not follow: ~4 KB a turn on disk, ~4 MB for a thousand turns,
  against a `models` registry that ships at 912 KB. What the ceiling cost was the
  thing `Playthrough::Feedback` exists to build — a flagged turn stays fully
  inspectable however long ago it was played. The cap survives as an opt-in
  escape hatch; do not make it the default again without a measurement that
  beats that one. Durable conversations are never pruned this way either.
- **`Playthrough#recap` is how a long game stays inside the window.** It spends
  `scenes.summary` — written by `Scene::Generator` on every arrival, and for
  exactly this — under a fixed character budget, so the narrator sees several
  turns of memory for about what one more full description would have cost. It
  asks no model anything. A narrated turn has no summary and contributes its own
  first sentence; do not "fix" that with a second call per turn.
- **Conversation history is progress, not world**, so `WorldSeed::Exporter`
  leaves it out and says so. See `db/seeds/worlds/README.md`.

### Generating the world

- `Location` is generated in two steps and carries `detail_level`: a **stub** is
  a name plus a one-line `teaser`, a **realized** location has the description
  and lore the player reads. `description` / `lore` are validated only when
  realized, so a stub saves. `Location::Generator#realize!` fills a stub in and
  stubs out its exits; it returns an already-realized location untouched.
  Generation happens once per place — do not add a code path that regenerates one.
- `Scene::Generator.opening(story)` narrates the story's opening arrival once,
  at world-building time, and marks it `is_opening`. `rake game:new` calls it so
  a generated world and a seeded one are the same shape; without it the first
  thing a player reads would depend on how the world was made.
- The description is saved BEFORE the exits are asked for, so a failed exits
  call does not throw away the more expensive of the two. The cost is that a
  room can end up realized with no way out, and `realize!` will not finish it;
  `Location::Generator#write_exits!` is public for exactly that recovery.
- `LocationConnection` rows are written in both directions from one answer, so
  anything stored on them has to be true both ways. That is why the travel
  method is a direction-neutral enum and the travel time is derived.
- **`Item::Registry` is the only thing in the app that creates an `Item`**, and
  it does so at realization, out of the SAME call that writes the description
  (`Location::DetailSchema`'s optional `items` array). Not a narrator tool and
  not a scan of prose — the engine owns what exists and `Playthrough::Moment`
  tells the narrator. Do not add a second writer, and do not add a third
  realization call for it. The array is optional on purpose: an empty required
  array reads as an omitted field to `BaseAgent#missing_schema_keys`, so a room
  honestly containing nothing would fail its own realization.
- The caps are on the ROOM and on the WORLD, read back from the records on every
  admission (`MAX_PER_ROOM`, `MAX_PER_STORY`) — the same distinction
  `Location::ExitsSchema::MAX_EXITS` documents, and for the same reason: rows
  arrive from outside the call. An item may never share a name with a person, a
  place, or another item in the story; two of the classifier's closed sets would
  answer to one word. A refused name costs the room its furniture and never its
  description.

### Seeded worlds

- `db/seeds/worlds/*.yml` are two checked-in playable worlds, loaded offline and
  idempotently by `db/seeds.rb`. `WorldSeed::Loader` matches on natural keys
  (story title, race name, character fullname, location name) — never on `id`.
- **A world places its own cast**, with `characters[].location`. That column is
  the closed set `talk` resolves against, so a world exported without it loads
  with nobody standing anywhere and nobody to speak to. The key is optional and
  an absent one means *nowhere*, which is a real state — `rake game:doctor`
  reports it, because somebody `Character.present_in` never offers is somebody
  the player can never speak to. The protagonist never carries one; see *Playing
  the world*. A `location` naming a room the file does not declare is refused,
  because that mistake is otherwise silent.
- **`characters[].absent: true` is nowhere ON PURPOSE**, and it is a different
  statement from an omitted `location`. `the-unrecorded-hour.yml` uses it on
  Perrin Lasco because that world is about him having been removed from it, and
  without it the doctor reported that world — correctly by its own rule and
  uselessly — on every single run. It writes `characters.deliberately_absent`,
  which is a fact about the person rather than a lookup: only three stories in
  the database have a checked-in file at all. `Story::Doctor` stays silent about
  a marked character who is nowhere, `Character::Registry` never places one
  (the second half of *never move somebody who is not nowhere*), and
  `Character#move_to!` CLEARS the marker — bringing them back is the story's
  business, and a person standing in a room is not absent from the world. The
  two keys are mutually exclusive and the loader refuses a file carrying both.
- **A world carries its own opening arrival**, as `opening_scene`. It is the one
  `Scene` that is world rather than progress, which is a line the exporter
  otherwise holds hard; `db/seeds/worlds/README.md` has the ruling and the two
  defects it closes. Its natural key is `scenes.is_opening`, it takes its
  `story_timestamp` from the story's `start_time`, and it deliberately does NOT
  stamp `Location#last_protagonist_visit` — a world built months ago is not
  somebody standing in a room. Do not "fix" that skip.
- `rake 'game:export[story_id]'` writes a generated world into that format.
  Rebuild the files with it after a schema change; the format, the rules the
  loader enforces and what is deliberately not exported are in
  `db/seeds/worlds/README.md`.
- The files are **authored artifacts**: edit them by hand. Re-export keeps the
  leading comment block and loses every comment below it.
- **Seeded worlds are not a substitute for generating one.**
  `test/lib/seeded_worlds_test.rb` is the only test that reads them; generator
  tests keep running against `FakeAgent`.

### Story time, and a world that moves on its own

- **`Story#clock` is what time it is in the fiction**, derived from
  `scenes.story_timestamp`, never stored and never the wall clock. A turn's
  scene is the previous scene plus what the turn cost:
  `LocationConnection.travel_minutes` for a journey, `Scene::TURN_MINUTES` for
  everything else. `Location#last_protagonist_visit` holds a story moment too.
  **Do not reach for `Time.current` anywhere on that path** — that was the
  defect, and a player could read it.
- **`WorldMechanic` is the world changing itself on that clock.** `kind` and
  `cadence` are keys into fixed tables in code, each naming a Ruby operation
  over records; a generated or hand-seeded world supplies parameters (which
  locations are `mobile`, how often, the in-fiction reason) and never behaviour.
  Same shape as `LocationConnection::DISTANCES`, and for the same reason. Adding
  a mechanic means adding a class under `app/models/world_mechanic/`, not a
  field somebody can fill in.
- `last_run_at` is a column in story time, so catching up is arithmetic on two
  datetimes: no timer, no job, nothing in memory, and a process that was down
  for a week pays the nights it owes on the next turn.
  `Playthrough::Turn#play` drives it. **It must stay free of model calls** —
  that is the whole claim, and `test/models/world_mechanic_test.rb` asserts it.
- **A mechanic that reports movement it did not perform is the failure mode this
  whole line of work exists to prevent.** So a rearrangement is judged on the
  **adjacency it induces** — the set of unordered pairs of places that end up
  joined — and never edge by edge or on array order: a permutation confined to
  one `mobile` location's own edges passes every per-edge check while leaving
  the graph identical. `ShuffleConnections#valid?` and `#settle` carry the
  argument. If you add a mechanic, the canonical form of the graph is what you
  compare; a night that changes nothing writes nothing.
- A `WorldEvent` is an audit trail, **not a narration source.** Two nights can
  return a place to the same neighbour, so replaying the log announces a change
  the player never experienced. Narration comes from a diff of what they were
  actually shown.
- `db/seeds/worlds/README.md` has the `mechanics` / `mobile` seed format and
  what `shuffle_connections` does to a graph.

### Playing the world

**[README.md](README.md#how-a-turn-works) has the diagram** — every branch of a
turn, and which boxes are model calls versus decisions from records. Read it
before changing the loop; the rules below are what it does not fit.

- **The loop is `Playthrough::Turn`, and its consumer's whole share of it is a
  string and a block.** `NarrationJob` broadcasts the chunks the block is
  yielded; it does not know which branch the turn took. Keep it that way — that
  block is what let SSE be swapped for Turbo Streams over Action Cable without
  touching a line of how prose is generated or persisted.
- The block is yielded **text**, not RubyLLM chunk objects. `Scene::Narrator`
  and `InteractionAgent` both unwrap before yielding; a schema'd branch yields
  its finished paragraph in one piece because it cannot stream at all.
- **`Playthrough::Classifier` resolves names back to records itself**, next to
  the candidate list it is the inverse of. It offers the model a closed enum of
  the room's exits, its cast, what is lying in it and what the player is
  carrying, so an answer either names a record that exists or names `nothing`.
  Do not move resolution into the loop and do not open the enum to free text: a
  fuzzy matcher on this seam guesses about where the player is standing and what
  they are holding.
- **ONE LINE, ONE ACT — AND A LINE THAT IS NOT ONE IS REFUSED WHOLE.** The
  captain's ruling of 2026-09-04: *"If someone tries to do two things or more at
  a time, we should refuse and prompt the player to pick only 1 thing. Or if we
  can't determine what they are trying to do, then we should refuse and ask for
  clarification. This can all be in the mechanics and doesn't need to go through
  narration."* `Playthrough::Classifier::Intent#refused?` is the predicate,
  `Playthrough::Refusal` is the one author of the sentence, and three shapes
  stop in front of the dispatch in both `Playthrough::Turn#play` and
  `Playthrough::Mechanics#act`: a line that named two things the records have, a
  reach the closed sets cannot answer, and an intent outside
  `Playthrough::IntentSchema::INTENTS` that still named a record. **A refused
  line writes nothing** — no row, no `Scene`, no visit stamp, no story time, no
  narrator call, no tokens beyond the classifier that had already run. It is not
  a `Scene` on purpose: `Scene#description` is read as NARRATION by
  `Story::Audit`, `Eval::Richness` and both frozen corpora, so engine copy in
  that column would be audited as prose a model wrote. **And it is still
  counted**: the `Playthrough::Overreach` or `Playthrough::Drift` row is taken
  inside `#classify`, before the loop asks whether it will play the line, so the
  ruling changed what a turn DOES and not what is measured.
- **WHAT IS NOT REFUSED, and the boundary matters as much as the rule.** A
  coherent non-mechanic line — `other`, or an `examine` that landed on nothing —
  is *not* undeterminable. "look at the sky", "wait", a remark to nobody: the
  classifier placed them, they reach for no record they could have missed, and
  they stay narrated. Refusing them would refuse everything that is not one of
  the acts that move a row. **An `examine` that named TWO things IS refused**,
  like any other line asking twice — since `ta-item-inscriptions` a look
  resolves a record, so `Playthrough::Overreach::ACTIONS` carries `examine`
  where `Playthrough::Drift::ACTIONS` deliberately does not: *a look can
  overreach and it cannot drift.* Two acts across two DIFFERENT closed sets
  ("take the stamp and go to the hallway") are also not refused, in either mode:
  `#also_record` resolves the second name through the action's own closed set,
  because a second and looser way into the records is what a closed set exists
  to prevent, and widening it would change what `Playthrough::Overreach` counts.
  That gap is pinned as a gap in `lib/engine_sweep/scripts/one-act-per-line.yml`.
- **`Playthrough::Drift` is still the counter for an unresolved reach**, one row
  per turn — see *Auditing the difference* below.
- **`take` and `drop` are the app moving a row, in that order: the record first,
  the sentence after.** `Item` is in exactly one of three places — lying in a
  location, held by one of the world's own people, or carried by the party of
  one playthrough — and the closed set each action resolves against is that
  distinction (`Item.lying_in`, `Playthrough#carried`). The narrator is then
  told what already happened, via `Scene::Narrator#narrate(command, fact:)`, and
  has no say in whether it is true. **Both directions or neither**: an app that
  owns picking up while the narrator asserts putting down has records that go
  stale the first time a player sets something on a table.
- **WHAT THE PARTY IS CARRYING IS THE PLAYTHROUGH'S, and this is the same
  argument as position.** It was `items.character_id` pointing at
  `story.protagonist` — one `Character` row per story — so every playthrough of
  one world shared one pair of hands, and the captain started playthrough 17 of
  a story holding what 16 had picked up. It is `items.playthrough_id` now, read
  through **`Playthrough#carried`, the one reader** (the classifier's closed
  set, `Playthrough::Moment`, the mechanics `carrying` line and the debug page
  all come through it) and written only by `#carry!` / `#put_down!`. Do not add
  a second copy of that query; that is how the room's cast came to disagree
  with the arrival paragraph.
- **The protagonist's own items are the story's STARTING INVENTORY**, not an
  inventory: world data out of a seed file's `characters[].items`, held by the
  protagonist row, carried by nobody, exported by the exporter, and given to
  each new playthrough as **its own copy** (`Story#starting_inventory`,
  `Playthrough#take_up_the_starting_inventory`). A copy rather than the row
  because a `Location` holds two parties at once and an `Item` does not, so
  handing position over by reference works and handing a thing over by
  reference would leave the second player empty-handed. `Item.in_story` is the
  one place the three-leg "every item in this world" query lives — a leg
  missing from a copy is an item the registry caps cannot see.
- **ROOMS STAY STORY-LEVEL and shared between playthroughs**, on the captain's
  explicit ruling: he is thinking about that separately. So a room one party has
  emptied is empty for the other, and
  `lib/engine_sweep/scripts/the-unrecorded-hour-two-players.yml` pins it either
  way — a future change to it fails a test rather than surprising somebody.
  Do not scope room contents per playthrough as a side effect of something else.
- **`Item::Registry` is the one thing in the app that creates an `Item`**, at
  room realization and out of the same call that describes the room. A seed file
  is the other writer and puts one in somebody's hands or on the floor
  (`locations[].items`); the registry leaves seeded rooms alone. See *Generating
  the world* above for the caps and the collisions it refuses.
  `Character::Registry` is its counterpart for people and rides on the same
  call — see above.
- **What is WRITTEN on a thing is a record, and `Item#readable` is the gate.**
  A note, a letter, a sign, a label: `items.inscription` holds the words, and
  `Playthrough::Turn#read_fact` hands them to the narrator verbatim and quoted,
  through the same `fact:` seam `take` uses. Two rules govern it and neither
  bends: **nothing generates text for an item the world did not mark readable**
  (so a ward stamp never grows a paragraph), and **the words are written once**
  — and neither cares which of `Item::PLACES` the thing is in: writing belongs
  to the note and not to the shelf, so a note lying in a room, one in an NPC's
  hands and one a party is carrying all keep their text, including the copy
  `Playthrough#take_up_the_starting_inventory` makes. The three writers are
  `Item::Registry` at realization, a seed file, and `Item::Inscriber` on the
  first read of a readable thing that arrived with none. A second reading is a
  database read and makes no call at all. Do not add a third writer, and do not
  re-generate — "a third writer" means a fourth place text can come from, not
  the copy above: the whole point is that the same note says the same thing
  twice.
  `inscription_misquoted` audits the difference, and its recall is deliberately
  poor — read `Story::Audit::Prose#inscription_quotes` before widening the cue
  list, because two widenings have already been measured and killed.
- **The three writes that move the world are named methods on
  `Playthrough::Turn`** — `#stand_in!`, `#carry!`, `#put_down!` — because
  `Playthrough::Mechanics` writes through the same ones. Put a new state change
  in a method there rather than inline in the branch that calls it, or the
  narration-off mode ends up with a second copy of it and starts testing itself.
- **What the player typed is `Scene#typed`**, written once in
  `Playthrough::Turn#play` rather than in each branch, so a branch added later
  cannot forget it. Do not go back to reconstructing it from the classifier's
  stored prompt: that survives only while the audit trail does, and
  `TA_CHAT_KEEP_TURNS` can still be set to prune it, which is how it used to
  disappear from older turns.
- **Who is standing in a room is a RECORD**, `characters.location_id`, and
  `Character.present_in(location)` is the closed set `talk` resolves against —
  the exact counterpart of `Item.lying_in` for `take`. Everything asks it
  through one method, `Scene::Generator.characters_present`, because the
  classifier must accept exactly the people the arrival paragraph introduced.
  It used to reconstruct the cast from the last scene in that location that had
  recorded *anyone*, and only an arrival records one — so a room nobody had
  walked into had nobody in it however central the person standing there was.
  Arriving at The Tide Post recorded the protagonist alone, on all three runs
  checked, in a world whose premise is a man chained to that post.
- **The PARTY is the one thing still derived, and has to be.** The protagonist
  and anyone `is_companion` are wherever the *playthrough* is
  (`playthroughs.current_location_id`), because two people playing one seeded
  world stand in two rooms at once and a story-level column cannot hold both.
  `Scene::Generator.characters_present` is the one place the party and the
  world's own people are added together.
- **Four things write a whereabouts and prose is not one of them**: the seed
  file's `characters[].location`, `Character::Registry` (which places somebody
  who is nowhere and NEVER moves somebody who is not — that rule is the Tide
  Post defect written down), the explicit `Character#move_to!`, and
  `rake game:backfill_whereabouts` once. Do not add a narrator tool, a
  per-turn model check, or a scan of prose for a name.
- **`Character::Registry` is the one thing that creates a `Character`** outside
  `rake game:new`, at room realization and out of the same call that describes
  the room — the people half of what `Item::Registry` does for the furniture,
  and the captain's *"rooms should be born with people in them sometimes."*
  **Who a new person is, the engine decides**: race, age and sex are rolled by
  `#slots` and stated in the prompt before the model answers, so build one
  registry per realization or the room is described around one person and
  written around another. It refuses a name a character, an item or a place
  already has, and a sheet the provider cut off — that last one is dropped
  rather than raised, because the call it would fail is the room's own
  description, already saved and the expensive half of the realization.
- **A `Scene`'s cast is a derived snapshot**, written from the records on every
  branch by `Playthrough::Turn#play` beside `typed` and `resolved_action`. It is
  kept rather than dropped because it answers a different question — where
  somebody WAS — which a column with no history cannot reconstruct and which
  `Eval::Richness`, `still_run` and both frozen corpora read. Do not read it
  back to decide who is present; that is the direction that forgot people.
- **Tools on the narrator were evaluated and rejected for movement** (see the
  ROADMAP): `gemma3:12b`, first in `LOCAL_MODEL_OPTIONS`, has no tool
  capability at all, and a model that cannot call tools does not fail — it
  narrates walking through a door and the player never moves. Tool support is
  slated to land with the narrator creating characters, where a missed call
  costs a record rather than the player's position.

### The mechanics on their own, with the narration off

`rake game:mechanics` (`Playthrough::Mechanics`, README → *Play the mechanics on
their own*) walks a world with **one** thing removed: the prose. It is the
instrument for the complaint it was built for — *"we are testing too many
variables at the same time"* — and the rules it lives under are short:

- **The classifier is KEPT and so is world generation.** Free text goes to
  `Playthrough::Classifier`, the resolved intent is printed as `understood:`,
  and a move is `Playthrough::Turn#move_to` whole — the stub is realized, the
  arrival is written, the visit is stamped. So the default path costs one model
  call a command and needs a key. Do not "simplify" it back to a grammar.
- **`Scene::Narrator` and `InteractionAgent` are the only things dropped.**
  `talk` and `examine` are refused with a line saying they are prose. If a
  branch needs prose, refuse it and say so; do not half-play it.
- **THE RULING'S REFUSALS ARE READ FROM THE SAME PLACE THE BROWSER READS THEM.**
  This mode used to do the first act of a two-noun line and add a note —
  `also named: copy-room apron -- one line is one act, so this turn did not
  touch it` — which was the honest report of exactly the half-played turn the
  ruling struck. `Playthrough::Refusal` is now the one author for both modes;
  this one reads `#reason` because it prints the whole engine read-out
  underneath, and the browser reads `#text`, which folds what IS here into the
  sentence. Do not write a second copy of either.
- **The arrival `Scene` is still written**, and its prose is not printed. That is
  deliberate: the cast, `last_protagonist_visit` and the story clock all hang off
  it, so skipping it would make the world this mode walks a different world.
- **`model: false` (`NO_MODEL=1`) is the offline fallback**, not the default: a
  fixed grammar, no generation, and a stub stays a stub. It exists for a machine
  with no key and for the engine-direct tests, and
  `Playthrough::MechanicsTest` runs that half with `BaseAgent.new` raising.
  The classifier half is driven through a `FakeAgent` whose queued responses
  ARE the calls the mode may make, so an accidental narrator call fails loudly.
- **Both modes write through `Playthrough::Turn`'s own writes** (`#move_to`,
  `#stand_in!`, `#carry!`, `#put_down!`) and read the closed sets off
  `Playthrough::Classifier`'s readers. Building a classifier costs nothing; only
  `#classify` talks to a model.
- **It is not `rake game:play`**, which is still ruled out. The moment it prints
  prose it becomes the second UI that rule exists to prevent.

### Sweeping the engine with stored scripts

`rake game:sweep` (`EngineSweep`, README → *Sweep the engine*) is the same
offline mode walked by stored YAML scripts instead of by a person, with
expectations asserted against the records after every typed line. It runs in
`bin/rails test`, so the engine is regression-tested on every build. The rules:

- **No model, and it is guarded rather than intended.** `EngineSweep.without_a_model`
  replaces `BaseAgent.new` for the length of a run. Never weaken that to make a
  script "work"; a sweep that made a model call would be a different instrument
  with the same name.
- **A step may name a `player:`, and a distinct name is a second `Playthrough`
  of the same loaded copy of the world.** It is the one thing a single walk
  cannot see: with the party's inventory on the story's protagonist row both
  games read the same hands, so no one-player script could tell a story-level
  inventory from a playthrough-level one. `the-unrecorded-hour-two-players.yml`
  is that script. A step with no `player:` goes to the default, so every other
  script is one playthrough and unchanged.
- **Every walk gets its own copy of the world**, loaded under
  `EngineSweep::Walk::TITLE_SUFFIX` inside a rolled-back transaction. A sweep
  must stay safe to run against a database somebody is playing in.
- **A script is a fixture, not a language.** `EngineSweep::Expectation::KEYS` is
  closed and an unknown key raises. Add a key only when the fact it asserts is a
  fact off the records; a sweep that started reading prose would be a worse copy
  of `Story::Audit`.
- **The invariants are the generator defects' own shape.** `EngineSweep::Invariants`
  checks the whole world after every walk because no typed line can open a door
  or overfill a room — `Location::Generator` does. They hold trivially today and
  that is not a reason to drop them. `cast_unmoved` is the same statement about
  people, and it compares against the world file rather than asserting "nobody
  is nowhere": nowhere is a state the checked-in worlds deliberately hold, so
  the file is the only honest thing to compare a walk with.
- **`present:` is what made presence sweepable at all.** Who is in a room was
  reconstructed from a scene an offline walk never writes, so it was invisible
  here by construction and the only place to observe it was a generated run
  costing money. It is a column now, so
  `lib/engine_sweep/scripts/the-salt-assizes-presence.yml` walks it for free.
- **Say what the sweep cannot see.** With the classifier off, a defect in how a
  model read a line is out of reach and belongs to `Playthrough::ClassifierTest`.
  `lib/engine_sweep/scripts/regressions-2026-09-03.yml` is the worked example:
  it names the five defects of that evening and which of them a walk reaches.

### Auditing the difference

The third clause of the standing constraint. `Story::Audit` walks stored
`Scene`s and reports where the prose and the records disagree (`rake
game:audit`); `Story::Scoreboard` turns the same sweep into numbers that move
(`rake game:score`). **Offline, deterministic, no model call, ~20 ms per
scene** — so both run over every scene ever written, on a whim, for nothing.
The debug view shows the same four tables for one playthrough.

- **Four categories, counted apart and never merged.** A CONTRADICTION is two
  records disagreeing (`unreachable_transition`, `item_not_held`,
  `unrecorded_departure`, `unrecorded_arrival`, `take_denied`,
  `pickup_invented`). A DEFECT is one passage wrong on its own terms
  (`truncated_prose`, `third_person_protagonist`). DRIFT is
  `Playthrough::Drift`: the player reached for something the closed sets do not
  have, which is how an invented exit becomes observable — by its consequences,
  not by scanning prose for a door.
- **THE TWO REACH COUNTS NOW MEASURE REFUSED TURNS, AND THEIR DENOMINATOR DOES
  NOT.** Since the ruling of 2026-09-04 a `reached_for_nothing` or
  `named_more_than_one` turn writes no `Scene`, and
  `Story::Audit#judgeable_for` counts scenes with a `typed` line — so both rates
  read as "reaches per *played* turn" from here on and can exceed 1 on a short
  run of mostly refused lines. Left as it is deliberately: changing what is
  measured in the same pass as changing what a turn does would make the movement
  since the baseline unreadable. The note is on the method. PACING (`still_run`) is not a defect at all
  and must never be counted as one: it is a stretch of turns on which the
  records show nothing happening with somebody in the room.
- **A check reads a STATE or it reads a CHANGE, and until 2026-09-03 they all
  read a state.** The records carried what the world IS after a turn and never
  what the turn DID, so the largest measured defect in the game — the narration
  denying a resolved `take` on 28 of 32 take turns of the 480-turn baseline —
  was invisible to every check, and a person reading a whole run found it.
  `Scene#resolved_action` and `Scene#acted_on` are the record that closed that
  gap, written by `Playthrough::Turn#play` beside `typed`, in the one place
  with the command and the scene on every branch. `take_denied` and
  `pickup_invented` are the first two checks that read one, and
  `unrecorded_departure` stopped inferring movement from two location ids
  (`Story::Audit#left_the_room?`). **When you add a record about the loop, add
  it there and nowhere else**, and read it back through
  `Scene#recorded_action` / `#acted_on_record` — a `Scene` also comes out of an
  `rake eval:run` database whose table was frozen before the column existed.
- **Every check answers to an error the captain named while playing**, in his
  own words, and nothing here was added because it sounded checkable. A new
  check needs a complaint behind it and a measurement in front of it.
- **PRECISION, NOT RECALL, and this is not a preference — it was measured.** A
  spike that asked "which known names appear in this prose" raised four flags on
  24 real narrations and all four were false positives: prose refers to places
  through windows and people in memory, so a mention is not a claim. There is
  therefore **no place check and no person check**, and adding one back needs a
  measurement, not an argument. `Story::Audit`'s header comment has the full
  reasoning for each check kept and each cut.
- **A whereabouts record did not revive the person check, and that was measured
  too.** `characters.location_id` made the records authoritative about presence,
  which was the stated blocker — and the corpora still cannot support
  `character_not_present`: 36 of 248 frozen passages are judgeable, exactly ONE
  names somebody recorded elsewhere, and moving one seeded character one door
  turns real, correct prose (*"From somewhere below, Grenn's voice rises"*) into
  a violation. `Story::Audit`'s finding 5 has the numbers and
  `Story::AuditPresenceTest` pins them, so the decision gets re-read rather than
  inherited. The gap is covered by the engine instead: `Character.present_in` is
  the closed set `talk` resolves against, so a player cannot SPEAK to somebody
  who is not there whatever the prose says about them.
- **Three corpora, pinned by three tests, and never pooled into one number.**
  `test/fixtures/files/narration_corpus.json` is 24 narrations two remote models
  really wrote, and `Story::AuditPrecisionTest` pins the item flags they earn.
  `test/fixtures/files/eval_corpus.json` is those 24 plus all 68 passages from
  the two worlds actually played — 92 in all — and
  `Story::Scoreboard::CorpusTest` pins the exact 19 flags they earn: all true
  positives, zero false positives, and **not one of the 24 lab narrations
  flagged**. `test/fixtures/files/transition_corpus.json` is 119 real `take` and
  `drop` turns with the transition each one made frozen beside the prose — the
  only corpus that can answer a check about a change — and
  `Story::Audit::TransitionTest` pins the 28-of-32 and 4-of-32 the baseline set
  earns, along with both stated misses and the fact that it carries held-out
  passages. Widening a pattern until it flags "There is no revolver, no pistol,
  no weapon of any kind on your person", or "the name is stitched into the
  strap… but it is yours", or "You lift the slate and set it on the bench",
  fails the build. If a set changes, read every new flag and sign for it before
  touching the fixture.
- **The three turns the captain actually judged are the validation**, and each
  is caught by a different check: `truncated_prose`, `still_run`,
  `unrecorded_departure`. A scoreboard that cannot catch the errors he noticed
  unaided is measuring something else.
- **His verdicts are ground truth and are reported as counts until there are
  enough of them.** `Story::Scoreboard::MIN_VERDICTS` is 30; below it the report
  prints CORRELATION UNESTABLISHED in words. Dressing up n=3 is the one thing
  this instrument must not do. It also names every turn he marked weak or bad
  that **no** check caught — that list is where the next check comes from.
- **The baseline is checked in (`db/eval_baseline.json`) and rewritten only when
  asked** (`SAVE=1 rake game:score`). Its git diff is the record of whether a
  change did anything. A scoreboard that re-baselines itself always reports no
  movement.
- **There is no prose score, no judge model, and no aggregate quality number**,
  and there must not be. See `Story::Scoreboard`'s header and
  `data/ta-model-bench/report.md` §9 (firstmate repo) for why. The offline
  model-read sweep is a separate, queued item (`ta-compliance-sweep`).
- **A check that cannot be run honestly is recorded as UNJUDGED, not guessed
  at.** A shuffled graph (`WorldMechanic` repoints edges, so today's graph is
  not the one the player walked), a scene with no story time, an item row
  touched after the scene was written. Keep that habit when adding a check.
- `Playthrough::Drift` is deliberately **not** pruned with the conversations. A
  chat is an audit trail nothing reads back; this is the measurement, and a
  measurement that expires cannot be watched over time.

### Measuring a change against the noise it makes

The automated half of the loop (`ta-eval-pipeline`). `rake eval:run` plays the
three seeded worlds through the real turn loop, keeps the rows, and scores them;
**[EVALUATION.md](EVALUATION.md) is the protocol and is the file to read before
using any of this.** What belongs here is the part that changes how you work:

- **A number from generated runs means nothing without its spread.** One
  unchanged configuration produced 1 to 13 `third_person_protagonist` flags on
  the same twenty turns of the same world. Never quote a count from a sweep
  without the min/max the board prints beside it, and never claim an improvement
  from one run against one run. **More turns is not a reliable cure** — the same
  extension halved one world's band and widened another's; see `Eval::Noise`.
- **`rake eval:compare BEFORE=… AFTER=…` is how a change is judged**, and its
  verdict is REAL, NOISE or INCONCLUSIVE. **Four runs a side is the floor** — at
  three the exact test cannot reach p ≤ 0.05 however clean the separation, so a
  verdict there would be reporting the sample size. `rake eval:null` checks the
  protocol cannot invent a difference out of one set split in half; run it if you
  change the rule.
- **Generation spends money and never runs in CI.** It refuses to start without
  `OPENROUTER_API_KEY`, prints an estimate first, and stops at $1.00 unattended.
  Scoring is offline, free and deterministic, and `Eval::PipelineTest` is the
  guard that the suite never touches the generating half.
- **Richness is printed beside the defect counts and is never added to them.**
  Prose that says less cannot contradict the records, so a fall in contradictions
  is only good news if `Eval::Richness` did not fall with it. It is not a quality
  score and it is gameable on its own; read it as a counterweight.
- **`The Salt Assizes` is held out by convention.** Tune on `Eval::TUNING`,
  report on `Eval::HELD_OUT`, and do not read a held-out passage while changing a
  check or put one in a fixture. Nothing enforces this today.
- **An eval script's talk beats must name no place.** A command that names a
  room the player can reach is a `move`, correctly, and it costs the run the
  branch the script existed to exercise. See the ROADMAP's known issues.
- **`Eval::MEASUREMENT_FILES` is the list an improving agent may not change.**
  Declared, not enforced; `rake eval:manifest` prints it with digests.

### When a world outlives the schema

A story is written once and then sits in the database while features land
around it, so a database holds stories of several vintages and the play path is
where the difference surfaces. **`rake game:doctor` is where it should surface
instead** — it asks the preconditions the play path asks, ahead of the play
path, and answers in sentences.

- `Story::Doctor` reports and never writes. Every check names, in its comment,
  the code that would otherwise be the first to notice — `PlaythroughsController`
  refusing a story with no realized location, `Story#clock` needing a
  `start_time`, `realize!` returning an exitless room untouched. **When that
  code changes, change the check with it**; a doctor reporting on a precondition
  the game no longer has is worse than none.
- `Story::Repair` acts only on what the doctor marked `:safe` (derivable from
  records already on file) or, with `generate: true`, `:generate` (worth a model
  call — a room, its exits, the opening arrival, and it says how many calls
  before it makes them). **It never invents data to make a validation pass.**
  Anything else is reported as `:manual` and left exactly as it was; for most
  such stories the honest answer is `rake game:delete`.
- **A one-time backfill recovers what a schema change left behind, and it
  refuses to guess.** `rake game:backfill_transitions`,
  `rake game:backfill_whereabouts` and `rake game:backfill_inventory` are all
  the same shape: offline, no model call, `DRY_RUN=1` first, and every outcome
  it could not derive reported by name rather than filled in with something
  plausible. A blank column says *not known*; a wrong one says something false.
  The one exception is stated out loud where it happens — `Item::InventoryBackfill`
  puts an unattributable item DOWN, in the room the last party that could have
  held it stands in, because an item nowhere is a state no closed set can offer.
- `Story::Deletion` prints a manifest, requires the story's **title** typed back
  (an id is precisely what gets mistyped), and destroys the universe only when
  no other story is built on it. `Story::DeletionTest` counts every table before
  and after rather than trusting the `dependent:` options — some are `nullify`,
  `Race`'s is `restrict_with_error`, and an edge's join rows are cleared by two
  separate HABTM declarations on `Location`.
- A dev server caches each table's columns on first use and a migration always
  runs in another process, so a server that was up before `db:migrate` serves
  models built from the old schema — which is `undefined method 'is_opening?'`
  for a column that exists. `StaleSchemaGuard` (development middleware) catches
  that and says restart; see the ROADMAP's *Known issues* for why it reports
  rather than repairs.

### A PR that needs a post-update action adds a step, not a sentence

**`bin/update` is the one command the captain runs after a pull**, and
`Update::REGISTRY` (`lib/update.rb`) is the list of what it then does to the
database he already has. So:

- **A PR whose code needs something run against existing rows adds a step to
  that registry**, and says in its body that it did. It does **not** add a hand
  list of commands to the PR description. Five PRs in one week each did
  (105, 109, 110, 111, 113), and the result was a captain reading five merged
  descriptions to work out what his own database still needed. A sentence in a
  merged PR body is not somewhere a checkout can look things up.
- Adding one is a file and a line: a subclass of `Update::Step` under
  `lib/update/steps/`, and its class in `REGISTRY` at the position it must run
  in. `lib/update.rb`'s header is the whole procedure and
  `Update::Steps::BackfillWhereabouts` is the shortest example.
- **Three rules, and `Update::RegistryTest` pins them.** A step must be
  IDEMPOTENT (running it on an already-updated database writes nothing and
  reports nothing to do — verify it by running twice, not by believing the
  backfill's own header), QUIET when it has nothing to do (a run against a
  current database has to be readable in one screen, or he stops reading it),
  and OFFLINE (no model call, no network, no key: this runs unattended against
  his primary development database). A refusal the step will never resolve —
  `ambiguous`, `unrecoverable` — is a `note`, not a change; counting those as
  pending work makes the tool cry wolf on every pull for ever.
- **A model call needs an explicit opt-in and nothing uses it.**
  `Update::Step.model_calls?` is the gate, built before anything needed it, and
  the registry test asserts nothing has passed through it. `Story::Repair`'s
  `generate:` half is exactly the shape of thing it is for, and
  `Update::Steps::SafeRepairs` passes `generate: false` in the open.
- The steps run in the registry's order because it is **dependency order**:
  `backfill_transitions` before `backfill_inventory` (attribution reads
  `Scene#took?`, which needs both columns the first one writes), every backfill
  before the repairs (a safe repair acts on findings a backfill removes), and
  the doctor last because it reports and never writes.

### Testing

- Generator tests **must not hit a model.** Use `FakeAgent`
  (`test/support/fake_agent.rb`) with `BaseAgent.stub(:new, agent)`. It records
  the prompts and schemas it was given, so assert on those.
- **`FakeAgent` writes no rows**, which is right for a test about what a
  generator does with an answer and wrong for a test about persistence. For
  that, use `OfflineExchange` (`test/support/offline_exchange.rb`): it stubs
  only `Chat#ask`, so the real `BaseAgent`, real `Chat` and `Message` rows, real
  token counts and real replay are all under test and only the HTTP call is not.
  `test/models/chat_persistence_test.rb` and
  `test/models/playthrough/turn_conversations_test.rb` are the two that use it.
  (`FakeChat` stood in for `RubyLLM::Chat.new`, which nothing constructs any
  more; it is gone.)
- The suite must run with **no API key and no ollama**, and that is now
  enforced rather than hoped for: `test_helper.rb` deletes
  `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `TA_DEBUG_VIEW`,
  `TA_CHAT_KEEP_TURNS` and `TA_CHAT_HISTORY_EXCHANGES`. All five change how the
  app behaves and all five are things you legitimately keep in `.env`. It takes
  **two passes** — once before `config/environment` is required, for the two
  that are frozen into `Chat` constants at class-load time, and once after,
  because `dotenv-rails` loads `.env` during that require and declines to
  override only the keys it finds already set, so the first pass hands it the
  opening to put them straight back. `RubyLLM.config.openrouter_api_key` is
  cleared too, since the initializer took its copy during the same require.
  Anything that needs one sets it inside the test and puts it back
  (`BaseAgentTest#with_env`), never reads it from the environment.
- **Factories must not roll dice.** A random default turns every test that
  reads the value into a lottery, and the failure lands on whoever runs the
  suite next rather than on whoever wrote the test. `location_connections`
  did this and cost a 1-in-35 flake that survived nine full runs and a re-run
  of its own seed — see **Known issues** in `ROADMAP.md` for why parallel
  workers made it unreproducible. Ask for a variation by trait, and pin the
  values a test actually asserts against in the test itself.
- Per `CLAUDE.md`: every model needs a test file and a factory.
- **An engine change earns a sweep script, not only a unit test.** A unit test
  written after a bug pins the bug; a script in `lib/engine_sweep/scripts/`
  walks the game a player walks and would have caught it. Both, and the script
  is the one that generalises — see *Sweeping the engine with stored scripts*.
- `bin/rails test` runs in about a second. There is no reason to skip it.

### Before you finish

```bash
bin/rails test
bundle exec rubocop
bin/rails zeitwerk:check   # app/agents/ uses PascalCase filenames; verify autoloading
```

## Environment

- Ruby 3.4.10 via asdf/mise (`.tool-versions`).
- `bin/rails db:prepare && bin/rails db:seed` — the dev database is not checked
  in, and the seed step fills the `models` table and loads the two playable
  worlds in `db/seeds/worlds`. Since the RubyLLM v1.7 `acts_as` migration that
  table **is** the model registry: RubyLLM resolves model names out of it and
  does not fall back to the registry the gem ships with, so an empty table
  resolves nothing. Reading it is offline; no API key.
- **The local rotation is OFF by default and needs `TA_LOCAL_MODELS=1`.** The
  captain's ruling, 2026-09-03: *"if we are still falling back to local models,
  let's stop doing that for now."* A local fallback does not fail, it ANSWERS —
  slowly, from a 4k-context CPU model — and every measurement downstream
  quietly becomes about a different model. With no key and no opt-in there is
  no model at all, and `BaseAgent::NoModelConfiguredError` says so in a
  sentence naming both ways out.
- With `TA_LOCAL_MODELS=1`, `ollama serve` must be running. Installed models are
  listed in `BaseAgent::LOCAL_MODEL_OPTIONS`; keep that list matching what is
  actually pulled, or every call fails on a missing model.
- `OPENROUTER_API_KEY` (kept in a gitignored `.env`, loaded by `dotenv-rails`,
  or `.envrc` for direnv users — both are gitignored) is strongly preferred
  for interactive work — local models take minutes per structured call, and on
  this machine run on CPU. `BaseAgent` uses remote models automatically when the
  key is set, working down `BaseAgent::REMOTE_MODEL_IDS` — `mistralai/mistral-medium-3.1`,
  then `minimax/minimax-m3` as a fallback. `OPENROUTER_MODEL` overrides
  the front of that list.

## Try it

```bash
rake 'game:new[a debt collector in a city built on a dead god]'
rake game:list
rake game:doctor   # what is wrong with each story, and what can be done about it
rake game:audit    # where the narration and the records disagree -- offline, no model call
bin/rails server   # then open http://localhost:3000 and play it
```

The rake tasks build worlds; the browser only plays them. There is no
`rake game:play` and there is not meant to be — the loop lives in
`Playthrough::Turn`, so a rake front end would be a second UI to maintain for
no new capability.

## The browser interface

Hotwire, and **genuinely zero build**: `propshaft` + `importmap-rails` +
`turbo-rails`, no Node, no `package.json`, no bundler step, no watch process.
That is a hard constraint from the captain, not an accident — `jsbundling-rails`,
`cssbundling-rails`, esbuild, Vite and any npm dependency are explicitly
refused. **If something appears to need one, that is a reason to reconsider the
something; stop and ask rather than adding a build step.**

Views are ERB with an inline `<style>` in the layout. Restyling is
`ta-api-iface`, a stage of its own — do not do it in passing.

- `ApplicationController < ActionController::Base` and `config.api_only = false`.
  That turns on `protect_from_forgery`, so every form goes through `form_with`.
- A browser session is bound to a `Playthrough` by its unguessable `token` in
  `session[:playthrough_token]`. There is no auth, no user model, and the
  captain does not want any: this is a single-player localhost app.
- **A turn is a job, and the play page is one Turbo Stream target.**
  `TurnsController#create` enqueues `NarrationJob` and answers immediately with
  a `replace` of `#turn_log`; the job broadcasts batched prose into `#stream`
  and then replaces `#turn_log` again with the finished turn, the location line
  and the input. There is no end-of-turn reload and no redirect carrying a
  `?command=` — both were consequences of streaming from the request.
  **Start with `bin/dev`** -- foreman, `Procfile.dev`, a `web` and a `jobs` line.
  A web process alone accepts a command and then narrates nothing, because the
  turn is sitting in the queue. Development also runs **`solid_cable`, not
  `async`** -- the turn is broadcast from the worker process and read by a
  WebSocket held in Puma, and `async` broadcasts only within one process. Three
  SQLite databases in development as a result; `bin/rails db:prepare` makes all
  three. Foreman is deliberately **not** in the Gemfile (it conflicts in a
  bundle); `bin/dev` installs it on demand, the way Rails' own generated one
  does. It is a process runner, not a build step.
- **Do not bind port 3000.** The captain runs his own long-lived server there.
  `PORT=3142 bin/dev` moves the whole formation; check a port is free before
  taking it, and never kill anything to free one.
- `turbo_stream_from` lives **outside** `#turn_log`. Inside it, the
  subscription would be torn down and rebuilt at the end of every turn and the
  next turn's tail would go to a channel nobody was listening on.
- The turn log's dimming rule is `.log:not(.streaming) > .turn:last-of-type`.
  Both halves are load-bearing: `streaming` on the wrapper says the newest turn
  is the `#stream` div outside the log, and `:last-of-type` is the marker with
  no class per entry. `PlaythroughsControllerTest`, `TurnsControllerTest` and
  `NarrationJobTest` all assert against those selectors.
- The only JavaScript is **one Stimulus controller**,
  `app/javascript/controllers/play_controller.js`: follow the narration down
  while the player is at the bottom, and put focus back in the input when a turn
  lands. Its scope is the wrapper on `playthroughs/show` and **not `#turn_log`**,
  which a Turbo Stream replaces at the end of every turn -- a controller there
  would be torn down by the very thing it exists to hook. Both its events are
  bound with `@window` / `@document` because neither reaches that element on its
  own.
- **Two things in that controller were found in a browser and will not fail a
  test if you break them.** It must WRAP `event.detail.render` rather than merely
  listen for `turbo:before-stream-render` -- Turbo awaits a repaint before it
  mutates, so the bare event measures stale layout and the follow drifts, 480px
  over one narration -- and it must focus with `preventScroll`. Arming happens in
  `connect()` **and** on `turbo:load`, which is not belt-and-braces: on a full
  page load `turbo:load` fires before Stimulus attaches and never arrives, and on
  a Turbo Drive visit `connect()` runs before Turbo applies the scroll. Each
  covers the case the other gets wrong.

### The debug view

`/playthroughs/:id/debug` — everything one playthrough generated and decided
behind the prose (`Playthrough::Debug`, `DebugController`, `app/views/debug/`).
Three rules govern it, and each exists because breaking it is easy:

- **Read, never write.** It must not generate, mutate a record or advance a
  playthrough — in particular it must never call `Story#catch_up_world!`,
  because looking at a world must not move it. Both tests snapshot every
  table's row count and newest `updated_at` across a full read, and the model
  test reads *every* public method, so an addition that writes fails a test
  that already exists.
- **Its own layout.** It shares no CSS with the game, which is what lets it be
  as dense as it likes while the reading experience stays deferred
  (`ta-api-iface`). Its whole mark on the game is one link on the play page.
- **Gated in the controller**, on `Playthrough::Debug.enabled?` — local by
  default, `TA_DEBUG_VIEW` overrides either way. Not only on the link: there is
  no auth, so a playthrough URL is the whole of a player's credentials.

It shows the branch each turn took **derived from the records that branch left
behind** rather than from a label, because there is no stored label — the
classifier's intent lives in memory inside `Playthrough::Turn#play`. Alongside
it, every prompt sent and every answer that came back, with the token counts and
the model that actually replied, out of `chats` / `messages`. What it still
cannot show it names rather than hiding, and anything new it cannot show should
be added to that list — **as should anything the list still claims and the code
has since fixed.** Two bullets were stale that way at once: a retention ceiling
that no longer applies by default, and a `scenes.typed` column that exists. A
false bullet in that panel is worse than a missing one, and
`DebugControllerTest` now pins both corrections.

**It overlaps `Story::Doctor` and must never be the quieter of the two.** Both
read the same rows: a one-way connection, two directions of one edge that
disagree, a distance or method outside the fixed tables. The division is scope —
the doctor reads every row of every story and is the one to trust; this reads
the room the player is standing in, and says so and links to `rake game:doctor`.
If you add a check to one and the same records are visible on the other, add it
to both or the project has two answers.

### The captain's verdict on a turn

`Playthrough::Feedback` — three buttons under every turn in the log, one click
each, plus an optional note once a verdict exists. An **evaluation instrument**
for `ta-narrator-model` and `ta-talk-model`, not a feature: real judgements on
real turns instead of blind reads of generated passages. Recorded on the play
page, reviewed on the debug page, gated on the same `Playthrough::Debug.enabled?`
as that page.

- **THE PROVENANCE IS FROZEN, NOT REFERENCED, and this is the rule to keep.**
  `Playthrough#prune_conversations!` destroys the one-shot conversations after
  `Chat::KEEP_TURNS` turns whenever a cap is set — and the default keeping them
  does not make the freezing redundant, it makes it belt and braces: an install
  that sets `TA_CHAT_KEEP_TURNS` must not silently lose its evaluation record.
  Without it `Chat#answering_model_ids` — the honest answer to
  which model replied, rotations included — resolves to nothing on any turn old
  enough to be worth comparing. `.record` therefore takes a **copy** on create:
  the model that wrote the prose, the whole prose attempt chain, the purpose,
  every model that answered the turn, the token counts. Amending a verdict must
  never re-snapshot; by then the receipts may be gone. Do not weaken the pruner
  to make a reference work — freeze what you need, and
  `Playthrough::FeedbackTest` is the test that proves it survived.
- **`prose_models` and `answering_models` are two lists on purpose.** A rotation
  in the classifier says nothing about the prose being judged, so `#rotated?`
  reads the first and never the second.
- **The `Scene` stays a reference.** Its `description`, `typed` and
  `story_timestamp` are never pruned, and a copy would be a second answer that
  could disagree with the prose the player actually read.
- **The footer under a turn is a `<footer>`, and that is load-bearing.** The log's
  dimming rule is `.log:not(.streaming) > .turn:last-of-type`, and
  `:last-of-type` counts elements of the same tag among their siblings — a
  `<div>` there silently becomes the last div and the newest turn stops reading
  at full strength. Four tests assert that selector.
- Recording answers with a Turbo Stream replacing **one** footer, so it cannot
  fight `NarrationJob`: neither side holds state, and the broadcast that ends a
  turn re-renders every footer out of the records.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
