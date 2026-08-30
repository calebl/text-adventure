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

### Talking to models

- All LLM calls go through `BaseAgent` (`app/agents/BaseAgent.rb`). It handles
  model selection and rotates to the next model when a call fails. Do not build
  a bare `RubyLLM::Chat` in new code.
- All LLM calls use structured output via `RubyLLM::Schema`. Schemas live
  alongside the model they populate (`app/models/universe/physical_schema.rb`).
- **Do not let `ruby_llm-schema` float.** It is pinned `~> 0.2` in the
  `Gemfile` for a reason: its 1.0.0 is a deprecation shim forwarding to
  `schematist`, and `ruby_llm` requires `ruby_llm-schema ~> 0`, so taking the
  shim silently pins `ruby_llm` to 1.8.2. Worse, the two disagree about what
  `to_json_schema` returns, and `RubyLLM::Chat#with_schema` then drops the
  schema with no error at all — every structured call goes out as prose.
  `test/models/ruby_llm_schema_envelope_test.rb` guards that seam all the way
  to the rendered request body; keep it passing.
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
  sequential calls on one agent, the way `Universe::Generator` and
  `Character::Generator` do; the conversation carries context between calls.
- Seed prompts with randomized "predetermined details" so repeated runs diverge
  (`Universe::Generator::TONES`, `Character::Generator::BIRTH_PLACES`).

### Testing

- Generator tests **must not hit a model.** Use `FakeAgent`
  (`test/support/fake_agent.rb`) with `BaseAgent.stub(:new, agent)`. It records
  the prompts and schemas it was given, so assert on those.
- For code that builds a `RubyLLM::Chat` directly rather than going through
  `BaseAgent`, use `FakeChat` (`test/support/fake_chat.rb`).
  `FakeChat.with_fake_chats(...)` replaces `RubyLLM::Chat.new` for a block and
  hands out queued responses, so a multi-pass agent's chats can be inspected in
  construction order.
- The suite must run with **no API key and no ollama**. Anything that needs a
  provider configured should set the key on `RubyLLM.config` inside the test and
  restore it, never read one from the environment.
- Per `CLAUDE.md`: every model needs a test file and a factory.
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
  in, and the seed step fills the `models` table. Since the RubyLLM v1.7
  `acts_as` migration that table **is** the model registry: RubyLLM resolves
  model names out of it and does not fall back to the registry the gem ships
  with, so an empty table resolves nothing. Reading it is offline; no API key.
- `ollama serve` must be running for local generation. Installed models are
  listed in `BaseAgent::LOCAL_MODEL_OPTIONS`; keep that list matching what is
  actually pulled, or every call fails on a missing model.
- `OPENROUTER_API_KEY` (kept in the gitignored `.envrc`) is strongly preferred
  for interactive work — local models take minutes per structured call, and on
  this machine run on CPU. `BaseAgent` uses remote models automatically when the
  key is set, working down `BaseAgent::REMOTE_MODEL_IDS` — `minimax/minimax-m3`,
  then `mistralai/mistral-medium-3.1` as a fallback. `OPENROUTER_MODEL` overrides
  the front of that list.

## Try it

```bash
rake 'game:new[a debt collector in a city built on a dead god]'
rake game:list
```

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
