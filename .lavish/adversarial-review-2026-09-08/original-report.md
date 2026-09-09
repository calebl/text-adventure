# Adversarial codebase review

The generated-location foundation works, but the current engine cannot yet deliver a world whose people and objects consistently act on their motivations, experiences and physical state. The largest gaps are executable NPC decisions, meaningful general actions, and memory/perception. Separately, normal failures and concurrency can corrupt the already-supported turn loop.

Reviewed commit 8dd1f5c on 2026-09-08. Traced world creation, lazy location realization, controller/job submission, classification, movement, dialogue, narration, inventory, combat, hazards, memories, world time/events, quests and existing test coverage. The full suite passed: 3,793 tests / 21,600 assertions. RuboCop passed for 490 files and Zeitwerk passed. Seventeen additional offline probes reproduced the reported behaviors, with 95 assertions. The probes assert observed defects, so passing means reproduced—not fixed. No live LLM calls were made; generated response examples are explicit fixtures. No application code or prompts were changed.

P1 means a core behavior or state-integrity issue; P2 means a narrower bug or an explicit limit. “Capability gap” and “Designed limit” distinguish goal mismatches from implementation bugs.

## R01 · P1 · NPC decisions do not become actions

**Capability gap.** A character can agree to a truce and immediately attack, promise to follow and remain behind, or hand over an item in dialogue while continuing to hold it.

InteractionAgent produces free-text action and inner_resolution fields. Turn#talk_to saves them into Interaction and a Scene; it does not resolve them into transfers, movement, a change of allegiance, or a future task. The only automatic NPC response in the turn loop is the combat riposte. Character movement during play and a general NPC decision scheduler are absent.

**Reproduction:** Three controlled exchanges reproduced this: the brass key remained in Maren’s hands, Maren stayed in the Market when the player left, and a narrated truce was followed by a recorded counterattack in the same turn.

**Scope:** The generated sentences in these probes were supplied by a fake provider. The proven defect is that the app has no mechanism to carry out or reject the proposed actions. This is not a measurement of how often a live model makes those proposals.

**Correction:** Give NPCs per-playthrough goals, relationships and actionable decisions. Have them choose from actions the engine can validate, apply the accepted result, and then narrate it. Begin with transfers, following, and de-escalation; do not execute free-text decisions directly.

Sources: [app/models/playthrough/turn.rb:559](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:559), [app/agents/InteractionAgent.rb:158](/home/calebl/Projects/text-adventure/app/agents/InteractionAgent.rb:158), [app/models/playthrough/riposte.rb:47](/home/calebl/Projects/text-adventure/app/models/playthrough/riposte.rb:47), [app/models/character.rb:544](/home/calebl/Projects/text-adventure/app/models/character.rb:544)

Probe(s): dialogue promises a transfer and following but applies neither; an NPC agreeing to cease fighting still attacks in the same turn.

## R02 · P1 · Ordinary physical actions can succeed only in prose

**Capability gap.** Drinking, unlocking, using a tool, burning an object, giving something to a person, or attempting a noncombat skill has no general engine action that can make the narrated outcome true.

The model-facing intents are move, talk, examine, take, drop, attack and other. A two-target throw is available through the slash grammar. The remaining branch sends raw input to Scene::Narrator and only persists a Scene. Universe laws and item descriptions do not turn those words into executable behavior. In particular, the drop operation puts an item on the floor, not in a named recipient’s hands.

**Reproduction:** With a correctly shaped other classification, “I drink the healing potion” stored “Your wounds close” in the scene while leaving HP unchanged and the potion in inventory.

**Scope:** This is a missing capability under the requested goal. The present engine deliberately owns a small vocabulary; that can support a constrained adventure, but arbitrary text currently suggests a broader range of effects than the engine provides.

**Correction:** Define a modest set of object affordances and actions with preconditions and effects. Resolve free text into those actions or an explicit unsupported attempt. Feed the actual result into narration so an unsupported act cannot masquerade as a completed state change.

Sources: [app/models/playthrough/intent_schema.rb:54](/home/calebl/Projects/text-adventure/app/models/playthrough/intent_schema.rb:54), [app/models/playthrough/turn.rb:194](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:194), [app/models/scene/narrator.rb:161](/home/calebl/Projects/text-adventure/app/models/scene/narrator.rb:161), [app/models/playthrough/turn.rb:665](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:665)

Probe(s): an other action can narrate consuming a potion without consuming or healing.

## R03 · P1 · Arrival narration contradicts the playthrough state

**Bug.** Revisiting a room can introduce a person you killed, restore an item to its old position in the description, or omit the harm just taken while entering.

Scene::Generator#characters_present reads the world’s cast without the dead-character filter in Playthrough#cast_in. Its arrival prompt reads the durable Location description and no playthrough inventory, conditions, or pending tolls. Turn#move_to applies arrival hazards before this call, then Turn#claim_tolls! marks those tolls as told by the arrival scene. The comments claiming that the arrival receives a Moment do not match the implementation.

**Reproduction:** After killing Maren and taking the brass key, the arrival prompt still explicitly listed her under “Who Is Here” and said the key was on the desk. The completed scene’s cast excluded her. A separate arrival toll was assigned to its scene even though neither its harm nor its save appeared in the prompt.

**Scope:** The prompt/state contradiction is deterministic. Whether the live narrator follows the wrong cast list or independently guesses the right outcome was not sampled.

**Correction:** Build an arrival context for the destination from the same per-playthrough readers used by ordinary turns. Include changes to inventory, dead and living cast, and the actual crossing result. Only mark events as presented after the render that received them.

Sources: [app/models/scene/generator.rb:174](/home/calebl/Projects/text-adventure/app/models/scene/generator.rb:174), [app/models/scene/generator.rb:202](/home/calebl/Projects/text-adventure/app/models/scene/generator.rb:202), [app/models/playthrough/turn.rb:482](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:482), [app/models/playthrough/turn.rb:1045](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:1045)

Probe(s): arrival prompt explicitly offers a dead person and original floor contents; arrival toll is marked told without being supplied to its narrator.

## R04 · P1 · Failed turns commit partial effects and retries repeat them

**Bug.** The failure message promises that the story is exactly where the player left it, but an item may already have moved or a hazard may already have charged them. Retrying can charge the hazard again.

Take and drop commit before narration. Arrival hazards commit before the arrival model call and before the player moves. A raised model error exits Turn#play before riposte, regular hazards and arc evaluation. NarrationJob displays one generic unchanged-state message and has no recorded turn identity or resumable phase. Scene::Narrator can also persist streamed partial prose on an ordinary exception.

**Reproduction:** A failed take kept the red coin in inventory, left the scene unchanged, and skipped a hostile NPC’s response. A failed arrival recorded one crossing toll while leaving the player in the old room; retrying successfully recorded a second toll for the same attempted crossing.

**Scope:** This report does not argue that committing state before narration is inherently wrong. The bug is that there is no complete, once-only engine outcome to resume or accurately report when rendering fails.

**Correction:** Record an idempotent turn and commit its full engine outcome once, including NPC responses and time. Treat narration as a resumable rendering step. A rendering retry must not replay an action, and the failure message must describe the actual committed state. Keep slow model calls outside SQLite write transactions.

Sources: [app/models/playthrough/turn.rb:636](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:636), [app/models/playthrough/turn.rb:482](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:482), [app/models/playthrough/turn.rb:250](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:250), [app/models/scene/narrator.rb:108](/home/calebl/Projects/text-adventure/app/models/scene/narrator.rb:108), [app/models/playthrough/turn_failure_notice.rb:27](/home/calebl/Projects/text-adventure/app/models/playthrough/turn_failure_notice.rb:27)

Probe(s): failed arrival charges crossing damage again on retry; failed take moves the item and skips the enemy response.

## R05 · P1 · Concurrent turns can lose history and generate a place twice

**Bug.** Two tabs or repeated submissions can complete two turns but retain only one in the active scene chain. Two players reaching the same stub can also overwrite its generated description.

TurnsController enqueues every submission. NarrationJob has no per-playthrough concurrency limit, while the queue runs multiple threads. Each turn reads and later replaces current_scene without a revision check. Location::Generator#realize! checks only the in-memory realized? flag, with no claim, recheck, or lock across competing realizations.

**Reproduction:** A deterministic interleaving at the narration boundary took two different coins. Both coins remained in inventory and two scenes pointed at the opening, but only one completed turn was reachable from current_scene. Separately, two objects loaded while a location was a stub both generated it; the second overwrote the first description.

**Scope:** The concurrency probe uses a controlled interleaving in one thread. It proves a permitted ordering that loses data; it is not a load-test estimate of frequency.

**Correction:** Serialize commands per playthrough and reject or queue duplicate turn identities. Protect commits with a state revision. Independently claim world realization per location so another playthrough waits for or reuses the completed result. Do not rely on hiding the form in one tab.

Sources: [app/controllers/turns_controller.rb:29](/home/calebl/Projects/text-adventure/app/controllers/turns_controller.rb:29), [app/jobs/narration_job.rb:44](/home/calebl/Projects/text-adventure/app/jobs/narration_job.rb:44), [config/queue.yml:7](/home/calebl/Projects/text-adventure/config/queue.yml:7), [app/models/scene/narrator.rb:164](/home/calebl/Projects/text-adventure/app/models/scene/narrator.rb:164), [app/models/location/generator.rb:119](/home/calebl/Projects/text-adventure/app/models/location/generator.rb:119)

Probe(s): interleaved turns overwrite one scene while keeping both item mutations; two loaded stubs can generate the same location twice.

## R06 · P1 · A generation failure permanently marks an unfinished room complete

**Bug.** A transient provider failure can remove a branch of future exploration. Revisiting does not finish the room, and an opening with no exits can remain sealed.

write_detail! commits detail_level: realized before admitting items and people and before realize! calls write_exits!. If a subsequent step fails, future realize! calls return immediately. There is an explicit write_exits! repair method and a unit test for manual repair, but the normal move path never resumes it.

**Reproduction:** The detail call succeeded and the exits call raised. The room stayed realized with only its existing way back. Calling realize! again made zero provider calls and generated no missing exits.

**Scope:** The existing header documents this tradeoff. It remains an operational bug in automatic exploration because recovery requires an operator to know and call an internal method.

**Correction:** Separate stored detail from completed realization. Persist resumable stage status and only expose a completed room once required admissions and exits are settled. A retry should reuse accepted detail and finish missing stages.

Sources: [app/models/location/generator.rb:119](/home/calebl/Projects/text-adventure/app/models/location/generator.rb:119), [app/models/location/generator.rb:339](/home/calebl/Projects/text-adventure/app/models/location/generator.rb:339), [app/models/location/generator.rb:356](/home/calebl/Projects/text-adventure/app/models/location/generator.rb:356), [test/models/location/generator_test.rb:987](/home/calebl/Projects/text-adventure/test/models/location/generator_test.rb:987)

Probe(s): exit failure permanently skips exit generation on retry.

## R07 · P2 · Fleeing combat corrupts the origin of the next journey

**Bug.** After escaping a fight, the player’s current location and current scene disagree. The next trip can cost the wrong amount of time and describe the wrong origin.

A move first installs the destination’s arrival scene. Fight#close! then appends a closing scene located in the room the fight began in and makes that current_scene. Scene::Generator#journey_minutes looks for an edge from previous_scene.location, not the actual origin of the new move. A missing edge silently falls back to adjacent travel time.

**Reproduction:** The player fled Market to Quay. current_location was Quay while current_scene.location was Market. A subsequent Quay-to-Tower connection priced at 20 minutes advanced the clock by 1 minute.

**Scope:** The fight summary referring to the old room is legitimate history. Treating that summary’s location as the party’s current movement origin is the defect.

**Correction:** Pass the actual move origin or walked connection to the arrival generator. Separate the location of a past fight from the party’s location after the turn. Add a flee-then-travel sweep and a full Turn-path test.

Sources: [app/models/playthrough/fight.rb:119](/home/calebl/Projects/text-adventure/app/models/playthrough/fight.rb:119), [app/models/scene/generator.rb:137](/home/calebl/Projects/text-adventure/app/models/scene/generator.rb:137), [app/models/playthrough/turn.rb:295](/home/calebl/Projects/text-adventure/app/models/playthrough/turn.rb:295)

Probe(s): fleeing closes combat in the old room then prices the next move from that room.

## R08 · P1 · NPCs lose important experiences and are not told about their own wounds

**Capability gap.** A character’s trust, resentment and behavior cannot reliably reflect earlier experiences. Even a recent attack can be absent from the character pass that decides their next response.

The durable chat replays two exchanges by default and deletes earlier messages. Moment#conclusions retrieves only the last six older interactions, under a 400-character budget, and reads only inner_resolution or action. There is no importance-based or relevant-memory retrieval. character_context supplies location name, time, company, one prior typed command and conclusions, but omits the NPC’s own condition, hostility and recorded blows. Attack turns generally write no Scene, so last_attempt does not capture them.

**Reproduction:** After nine exchanges, an initial “Iri murdered my brother; I will never trust her” resolution was still stored but absent from the character context. After an engine-recorded attack on a surviving NPC, that context still contained no wound, blow or fighting state.

**Scope:** Persisting Interaction rows prevents archival loss. It does not give a model access to the omitted experience. Exact live-model reactions were not evaluated.

**Correction:** Maintain durable per-game relationships and salient memories with references to witnessed events. Retrieve relevant experiences, not only recent ones. Supply verified perception of injuries and conflict before asking for a response; distinguish what each NPC witnessed from global history.

Sources: [app/models/chat.rb:59](/home/calebl/Projects/text-adventure/app/models/chat.rb:59), [app/models/chat.rb:137](/home/calebl/Projects/text-adventure/app/models/chat.rb:137), [app/models/playthrough/moment.rb:246](/home/calebl/Projects/text-adventure/app/models/playthrough/moment.rb:246), [app/models/playthrough/moment.rb:283](/home/calebl/Projects/text-adventure/app/models/playthrough/moment.rb:283), [app/models/playthrough/moment.rb:445](/home/calebl/Projects/text-adventure/app/models/playthrough/moment.rb:445)

Probe(s): important NPC conclusions fall out after enough small exchanges.

## R09 · P2 · The world eventually stops admitting people and items

**Designed limit.** Exploration can keep creating places while meaningful new encounters and takeable contents disappear.

Character::Registry::MAX_PER_STORY is 12 and counts every character, including the protagonist and dead characters. Once reached, allowance is zero and the room prompt explicitly says to write nobody. Item::Registry::MAX_PER_STORY is 60 distinct template names. These are whole-world ceilings, not limits on the current context window.

**Reproduction:** At the character ceiling, a new room marked “a crowd” had zero allowed people and a “Write NOBODY” prompt. At the item ceiling, its item allowance was also zero.

**Scope:** These are intentional constraints in file headers, not accidental off-by-one errors. They conflict with sustained exploration under the goal in this review. Seeded worlds can bypass some generation caps; that does not help newly explored rooms.

**Correction:** Bound model context and per-room generation cost independently of total world population. If a finite adventure is intended instead, make that scope explicit and ensure the arc ends before the world becomes empty by policy.

Sources: [app/models/character/registry.rb:178](/home/calebl/Projects/text-adventure/app/models/character/registry.rb:178), [app/models/character/registry.rb:279](/home/calebl/Projects/text-adventure/app/models/character/registry.rb:279), [app/models/character/registry.rb:302](/home/calebl/Projects/text-adventure/app/models/character/registry.rb:302), [app/models/item/registry.rb:86](/home/calebl/Projects/text-adventure/app/models/item/registry.rb:86), [app/models/item/registry.rb:129](/home/calebl/Projects/text-adventure/app/models/item/registry.rb:129)

Probe(s): reaching the world cast cap forces even a populated new room to be empty.

## R10 · P2 · Visit history leaks between playthroughs

**Bug.** A new player can be told they recognize a place they have never entered, because a different playthrough visited it first.

Location.last_protagonist_visit is a single world-level timestamp, updated by every non-opening Scene. Arrival generation treats any value there as proof that this player has stood here before. It never checks this playthrough’s scene chain. There is a related design tension: playthrough time is local, while world mechanics and scheduled events run from the maximum time across all scenes.

**Reproduction:** Two playthroughs began on the same opening scene. After the first visited Tower, the second player’s first arrival prompt said “has stood here before.” A separate probe confirmed that a game at the opening time runs event catch-up against another game’s later clock.

**Scope:** The global world clock is explicitly chosen in Story’s header. Sharing another player’s personal recognition is a bug regardless. Whether world changes should be shared across independent timelines needs an explicit product decision.

**Correction:** Store visits per playthrough and derive recognition from those records. Preserve the shared generated geography. Decide separately whether games share a synchronized world clock or keep per-game mutable world overlays.

Sources: [app/models/scene/generator.rb:83](/home/calebl/Projects/text-adventure/app/models/scene/generator.rb:83), [app/models/scene.rb:353](/home/calebl/Projects/text-adventure/app/models/scene.rb:353), [app/models/location.rb:436](/home/calebl/Projects/text-adventure/app/models/location.rb:436), [app/models/story.rb:87](/home/calebl/Projects/text-adventure/app/models/story.rb:87), [app/models/playthrough.rb:296](/home/calebl/Projects/text-adventure/app/models/playthrough.rb:296)

Probe(s): one playthrough makes a second player's first visit a return; world catching up fires another game's event from the global maximum clock.

## R11 · P2 · Scheduled world events have no consequences yet

**Capability gap.** A scheduled explosion, fire or quest ramification can be marked as happened while the world, people and narration continue unchanged.

WorldEvent#fire! only writes fired_at. There is no effect dispatcher for these events and neither the normal Moment context nor the arrival context reads their summaries. WorldMechanic does provide an actual graph-shuffling operation, but that does not execute arbitrary scheduled event descriptions.

**Reproduction:** A scheduled “The market burns to the ground” event fired. The associated location’s attributes were unchanged and the event did not appear in the narration context.

**Scope:** The record-only behavior is documented as groundwork for a later reader. This is a missing capability, not a claim that the schedule fails to set its timestamp.

**Correction:** Give scheduled events validated effect kinds and parameters, then apply those effects idempotently and publish their observable results to affected NPCs and narration. Keep an event’s prose summary descriptive; never treat it as executable code.

Sources: [app/models/world_event.rb:159](/home/calebl/Projects/text-adventure/app/models/world_event.rb:159), [app/models/story.rb:110](/home/calebl/Projects/text-adventure/app/models/story.rb:110), [app/models/world_mechanic.rb:26](/home/calebl/Projects/text-adventure/app/models/world_mechanic.rb:26), [app/models/playthrough/arc.rb:347](/home/calebl/Projects/text-adventure/app/models/playthrough/arc.rb:347)

Probe(s): a scheduled catastrophe fires without changing the named location or narration context.

## R12 · P2 · Generated alternative endings cannot be selected

**Bug.** New worlds pay to generate several possible endings, but only their default ending can ever be reached by the current selector.

Quest::Schema asks for outcome name, summary and is_default; it has no condition field. Quest::Generator#write_outcomes! persists only those fields. Arc#outcome_reached examines conditional outcomes and otherwise picks the default. Thus every non-default generated outcome lacks the condition required to enter selection. Hand-authored seeded outcomes can work because they can supply conditions.

**Reproduction:** Generating a valid-shaped three-step quest with two outcome fixtures wrote both endings and zero conditional outcomes. Arc#satisfies? returned false for the non-default ending.

**Scope:** A separate limitation remains even after this bug is fixed: speak_to checks for any Interaction, not whether persuasion or negotiation succeeded. Quests should only claim the semantics that their engine predicates actually verify.

**Correction:** Generate from a closed set of supported outcome conditions and validate that each alternative is reachable. Align outcome prose with the condition the engine can prove. Add semantic action outcomes before making successful persuasion a completion requirement.

Sources: [app/models/quest/schema.rb:107](/home/calebl/Projects/text-adventure/app/models/quest/schema.rb:107), [app/models/quest/generator.rb:158](/home/calebl/Projects/text-adventure/app/models/quest/generator.rb:158), [app/models/playthrough/arc.rb:318](/home/calebl/Projects/text-adventure/app/models/playthrough/arc.rb:318), [app/models/playthrough/arc.rb:422](/home/calebl/Projects/text-adventure/app/models/playthrough/arc.rb:422)

Probe(s): generated alternative endings have no reachable condition.

## What the passing suite establishes

The sweep exercises Playthrough::Mechanics against isolated seeded worlds; it shares mutation helpers with Turn, but it does not run every browser-path orchestration step or model rendering boundary. Many unit tests validate each component in isolation. Those checks remain useful, but their green results do not establish realistic social behavior, once-only failure recovery, concurrency safety, or agreement between every narrator prompt and current game state.

## Recommended order

First stabilize turn identity, concurrency, resumable generation and arrival context (R03–R07). Then build one complete social interaction across perception, relevant memory, a proposed action, engine validation and an observable consequence (R01, R02, R08). Revisit the world ceilings and event/ending semantics before expanding exploration (R09–R12). Preserve the durable Location / per-playthrough state split. Prompt changes should follow the repository’s stored-baseline evaluation protocol; stronger instructions alone cannot implement missing state transitions.

The reproduction script is [probes.rb](probes.rb). Run it from the repository root with `PARALLEL_WORKERS=1 bundle exec ruby .lavish/adversarial-review-2026-09-08/probes.rb`. It uses the test database and transactional fixtures. The review does not benchmark provider latency, live-model output frequencies, or production throughput.
