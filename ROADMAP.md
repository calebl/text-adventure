# Roadmap

Working status and the task queue for Text Adventure. Update this file as work
lands — it is the single place that records what is built, what is next, and why.

**Core idea:** a text adventure that generates itself as you explore. The world
is generated on demand, and once generated it persists — walk back into a room
and it is the room you left.

## The persistence model

This is the load-bearing design decision, and the schema already encodes it:

- **`Location` is the durable world.** Name, description, `lore`, the
  `location_connections` graph (with `distance` / `time_to_travel` /
  `travel_method`), `parent_location` for containment. Generated once, then
  reused forever.
- **`Scene` is a moment in that world.** `belongs_to :location`, plus a
  `previous_scene` linked list and a `story_timestamp`.

So revisiting a place reuses the persisted `Location` while creating a new
`Scene`. The world stays fixed; time still moves. Generation happens at the
`Location` boundary, never twice for the same place.

## Status

### Done

- Rails 8 API app, SQLite, 117 tests green.
- Full schema: `Universe` → `Story` → `Location` / `Character` / `Scene` /
  `Interaction` / `Item`, plus the `location_connections` graph.
- `Universe::Generator`, `Story::Generator` — bootstrap a world from a premise.
- `Character::Generator` — two-pass (base attributes, then background). Races
  are assigned from the universe's list, not invented per character.
- `Playthrough` model — a session's position in a story (protagonist,
  `current_location`, `current_scene`, session `token`), plus `is_protagonist`
  on `Character`. State layer only; nothing reads or writes it yet.
- `Race` model — `Universe has_many :races`, `Character belongs_to :race`, with a
  validation that a character's race comes from its own story's universe.
- Explicit lengths (`max_length` plus a stated sentence count) on every schema
  field. Without them a strong model answered "Race of the character" with 2,382
  characters of prose; the whole character sheet is now ~2,530 characters.
- `BaseAgent` — RubyLLM wrapper with model fallback on failure.
- `rake game:new[premise]` / `rake game:list` — generate and inspect worlds.
- `InteractionAgent` — two-pass character-then-narrator dialogue.
- `ruby_llm` 1.16 + `ruby_llm-schema` 0.4, on RubyLLM's association-based
  `acts_as` API. The `models` table is the model registry now; seed it with
  `bin/rails db:seed`, or nothing resolves.
- AI-layer test coverage: `Narrator`, `InteractionAgent`, the three schema
  classes, and `Chat` / `Message` / `ToolCall` / `Model`, all stubbed at the
  RubyLLM boundary.

### Not built yet

There is still **no game loop**. You can generate a world but not walk around
in it. That is the whole of the next milestone.

## Next up

### 1. Location generation with stubs

The gap that blocks everything else. When the narrator says "three doors lead
out," all three exits must exist as `Location` records before the player picks
one — but only the one they walk through should be fully generated.

- [ ] Migration: add a `detail_level` (or `generated_at`) column to `locations`
      distinguishing a **stub** (name + one-line teaser) from a **realized**
      location. Today `Location` validates `description` and `lore` as present,
      so stubs cannot be saved at all.
- [ ] `Location::Generator` — realize a stub: full description, lore, and the
      stub exits leading out of it.
- [ ] Generate the story's opening location as part of `game:new`.

### 2. The protagonist

- [x] The player is a `Character` with `is_protagonist` set — at most one per
      story, enforced by validation and exposed as `Story#protagonist`.
- [x] Position lives on a separate `Playthrough` model (`story`, `character`,
      `current_location`, `current_scene`, unguessable unique `token`) rather
      than columns on `Story`. Same split the schema already makes between the
      durable `Location` and the momentary `Scene`: the world is not somebody's
      progress through it, and one generated world can be played twice. The
      `token` is what will bind a browser session to a playthrough.
- [ ] Nothing writes either yet — `Character::Generator` never sets
      `is_protagonist` (nor `is_companion`), and no code creates a
      `Playthrough`. That belongs to the game loop and the browser interface.

### 3. Scene generation

- [ ] `Scene::Generator` — given a `Location` and the `previous_scene`, narrate
      arriving. Must read differently on a first visit versus a return, using
      `Location#last_protagonist_visit` and `#time_since_last_visit` (both
      already implemented and unused).
- [ ] Populate `scene.characters` from who is present.

### 4. The game loop

- [ ] Classify player input: move / talk / examine / take / other.
- [ ] On **move**: resolve the target from `connected_locations`. If it is a
      stub, realize it. Then generate a `Scene` there. This is the load-or-generate
      seam that makes the whole idea work.
- [ ] On **talk**: hand off to the existing `InteractionAgent`.
- [ ] `rake game:play[story_id]` — the first genuinely playable interface.

### 5. Persistence and history

- [ ] Wire up the `chats` / `messages` / `tool_calls` tables. `Chat`, `Message`
      and `ToolCall` already call `acts_as_chat` and friends, but every agent
      builds a bare `RubyLLM::Chat`, so **nothing is ever persisted**. Quitting
      loses all conversation state.
- [ ] Set `Interaction#inner_resolution` — `Interaction#completed?` tests it and
      nothing ever writes it.
- [ ] Summarize old scenes so long playthroughs stay inside the context window.

### 6. Interface

- [ ] `config/routes.rb` is empty. Add API endpoints once the rake loop proves
      the design.

## Known issues

- **Local models are slow, and they run on CPU here.** `ollama ps` reports
  `size_vram: 0`, so nothing is GPU-accelerated on this machine. Measured on a
  small 3-field schema: `gemma3:12b` ≈ 39s, `qwen3:8b` ≈ 92s (it burns the budget
  on thinking tokens). Paragraph-length schemas like `Universe::PhysicalSchema`
  take *many* minutes and exceeded RubyLLM's 120s default request timeout, which
  surfaced as `Faraday::TimeoutError` and looked exactly like a broken model.
  `config.request_timeout` is now 600s, overridable via `LLM_REQUEST_TIMEOUT`.
  Set `OPENROUTER_API_KEY` for anything interactive; `BaseAgent` prefers remote
  models automatically when the key is present.
- **A model that ignores your schema is worse than one that fails.** OpenRouter's
  `:free` endpoints frequently accept a JSON schema and answer in prose anyway --
  `minimax/minimax-m3:free` does exactly this, while the paid `minimax/minimax-m3`
  honors it. Ruby's `String#[]` does substring matching, so `content["fullname"]`
  on a prose response returns `"fullname"` rather than raising, silently poisoning
  the record. `BaseAgent#verify_schema_honored!` now raises `SchemaIgnoredError`
  and rotates to the next model. It also rejects a Hash that came back missing
  required fields, which is the same failure one step further along.
  **Before adding any model, check it:**
  `curl -s https://openrouter.ai/api/v1/models | jq '.data[] | select(.id == "MODEL") | .supported_parameters'`
- **`Character#interaction_instructions` is ~3,200 tokens per turn.** Bounded
  fields brought the character sheet down to ~2,530 characters, but the method
  still inlines the entire universe (`Universe#prompt_details`, which now
  includes every race) on every single turn of dialogue. Interactions should
  eventually get a trimmed universe summary rather than the full record.
- **Watch the ollama context window.** `ollama ps` reports `context_length: 4096`
  for these models. The universe prompt plus ten paragraphs of output is already
  close to that, and `Story::Generator` feeds the whole universe back in. Scene
  generation will need summarized context rather than the full record.
- **`Narrator`** (`app/models/narrator.rb`) predates the schema and never reads
  a single database record — no `Scene`, no `Location`, no `Character`. It is a
  freestanding chat prompt whose system directive describes tools
  (`get_scene_details`, `get_universe_rules`) that do not exist. Either rewrite it
  as the narration layer over `Scene::Generator` or delete it; do not build on it.
- **`InteractionAgent`** hardcodes `cognitivecomputations/dolphin-mixtral-8x22b`
  and bypasses `BaseAgent` entirely. It should use `BaseAgent` so it inherits
  model fallback. Its two-pass character→narrator structure is worth keeping.
- **`Character::Generator` prompts for `sex` and `age`** in the "predetermined
  details" block, but `Character::BaseSchema` also asks the model for them, so
  the roll is advisory. Either drop them from the schema or stop rolling them.
- **`InteractionAgent#narrator_instructions` is shadowed.** The `attr_reader`
  on line 2 is overwritten by the two-argument method below it, so the
  `@narrator_instructions` set during `ask` is unreachable and calling the
  reader raises on arity. Pinned in `test/agents/interaction_agent_test.rb`.
- **The narrator prompt interpolates the enum key, not the value.**
  `Character#sex` is an ActiveRecord enum, so it reads back `"non_binary"`
  while the pronoun rule two lines below keys on `"non-binary"`; `transgender`
  has no pronoun rule at all. Same file, pinned the same way.
- **`Narrator::DEFAULT_MODEL` does not resolve.**
  `cognitivecomputations/dolphin-mixtral-8x22b` is in neither the bundled
  registry nor the seeded `models` table, so `Narrator.new` raises
  `RubyLLM::ModelNotFoundError`. Pre-existing — it failed on ruby_llm 1.8.2 too.
  `InteractionAgent` hardcodes the same model.
- **`BaseAgent::LOCAL_MODEL_OPTIONS` do not set `assume_model_exists`**, and
  ollama models are not in the registry, so local-only runs fail to resolve.
- The migration to the new `acts_as` API left `chats.model_id_string` and
  `messages.model_id_string` behind — dead columns the generator's `down` step
  needs. Drop them if the migration is ever squashed.
- The `async` gem is still in the `Gemfile` but no longer used after
  `Character::Generator` was made synchronous.
