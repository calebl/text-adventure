# One conversation with a model, and every message in it.
#
# THE GRANULARITY IS ONE CHAT PER AGENT CONVERSATION -- per `BaseAgent`
# instance -- not per turn and not per playthrough. A chat's `messages` have to
# be a list you could send to a model again: one system instruction, one
# schema, one model. Merging a turn's four agents into one row would produce a
# message list that is not a conversation with anybody -- the classifier's
# closed enum answering the narrator's prose prompt -- and merging a whole
# playthrough is the same objection fifty times over, plus a row that never
# stops growing.
#
# WHICH TURN a message belongs to is therefore recorded on the MESSAGE
# (`messages.scene_id`), not on the chat. A durable conversation spans many
# turns, so a `chats.scene_id` would have to be last-one-wins and a turn's cost
# could not be totalled at all. See `BaseAgent#attribute_to!`.
#
# ONE-SHOT VERSUS DURABLE. Almost every agent here is stateless by design: it
# assembles its context out of records on each call, so its chat is written
# once, read never, and kept only as the audit trail the debug view reads.
# `Chat::CHARACTER` is the exception -- see `.conversation_with`.
class Chat < ApplicationRecord
  acts_as_chat

  # Talking to somebody. The one conversation that is PICKED UP AGAIN rather
  # than started fresh, keyed by (playthrough, character): a character who
  # forgets the previous sentence the moment the turn ends is the conversation
  # state that quitting used to lose.
  CHARACTER = "character".freeze

  # Every kind of conversation the app has, as a key rather than free text so
  # the debug view and the pruner can both reason about them.
  PURPOSES = [
    "classifier",           # Playthrough::Classifier -- what did the player mean
    "arrival",              # Scene::Generator -- walking into a place
    "narration",            # Scene::Narrator -- answering the typed command
    CHARACTER,              # InteractionAgent, first pass -- the character
    "interaction-narration", # InteractionAgent, second pass -- the prose
    "location",             # Location::Generator -- realizing a room
    "inscription",          # Item::Inscriber -- what a readable thing says, once
    "world"                 # the world-building generators, off the turn path
  ].freeze

  # HOW MUCH OF A DURABLE CONVERSATION IS REPLAYED, in exchanges (one exchange
  # is the player's line plus the character's answer).
  #
  # Two, and the number is arithmetic rather than taste. The local models here
  # run on CPU with a 4,096-token context, and `Character#interaction_instructions`
  # inlines the whole universe -- measured at ~1,000 tokens for the seeded
  # worlds, and it grows with the universe. Two exchanges is ~360 tokens of
  # history; the prompt on top is ~30, and the schema'd answer needs ~200. That
  # leaves room on a 4k window with the largest seeded universe, which is the
  # binding case. Raise it only against a measurement.
  #
  # Nothing is lost by the ceiling: what the character actually decided is kept
  # in full on `Interaction` -- five fields, `inner_resolution` and a summary,
  # one row per exchange, forever. The chat holds the recent verbatim exchange;
  # the interactions hold the memory.
  HISTORY_EXCHANGES = ENV.fetch("TA_CHAT_HISTORY_EXCHANGES", 2).to_i

  # HOW MANY TURNS OF ONE-SHOT CONVERSATION ARE KEPT, per playthrough.
  #
  # NIL BY DEFAULT, MEANING KEEP EVERYTHING. Set `TA_CHAT_KEEP_TURNS` to opt
  # into a cap; nothing is pruned unless you do.
  #
  # This used to default to 25, on the reasoning that a playthrough is a SQLite
  # file on a laptop, that every turn writes three or four chats, that an
  # arrival prompt inlines the universe, and that the audit trail is therefore
  # the biggest thing a long game accumulates. Every clause of that is true and
  # the conclusion still does not follow, because none of it was measured
  # against a number. Measured over 500 real turns driven through the loop:
  #
  #   messages written per turn       6
  #   average message content         ~520 bytes
  #   messages + chats, on disk       4.16 KB per turn
  #   => 100 turns                    0.41 MB
  #   => 1,000 turns                  4.1 MB
  #   `models`, which SHIPS with the app   912 KB (1,166 rows)
  #
  # So the registry the app installs with outweighs a 200-turn playthrough's
  # entire audit trail, and a thousand-turn game costs four megabytes. The trail
  # being the largest thing the GAME accumulates is a statement about how little
  # else it writes -- five scenes and a few characters -- not about the trail
  # being large. A laptop is not troubled by either.
  #
  # What keeping them buys is the point. A turn the player flagged stays fully
  # inspectable -- prompt, answer, model, token counts -- however long ago it was
  # played, which is the evaluation record `Playthrough::Feedback` exists to
  # build. Growth was checked as well as sized: the debug page preloads a
  # playthrough's messages in a fixed number of queries, so keeping every turn's
  # receipts costs it no extra query at all (measured identical at 500 turns).
  #
  # `Playthrough#prune_conversations!` applies this, and does nothing while nil.
  KEEP_TURNS = ENV.fetch("TA_CHAT_KEEP_TURNS", nil).presence&.to_i

  # WHETHER A RETENTION CAP IS IN FORCE AT ALL. For the views that have to
  # DESCRIBE the rule rather than apply it: with no cap there is no "older than
  # N turns", and interpolating a nil into that sentence reads as a bug.
  def self.capped? = !KEEP_TURNS.nil?

  belongs_to :playthrough, optional: true
  belongs_to :character, optional: true

  validates :purpose, inclusion: { in: PURPOSES }, allow_nil: true

  scope :durable, -> { where(purpose: CHARACTER) }
  scope :one_shot, -> { where.not(purpose: CHARACTER).or(where(purpose: nil)) }

  # THE ONE CONVERSATION THAT IS RESUMED. Same playthrough, same character, same
  # chat -- so walking away and coming back an hour (or a server restart) later
  # continues the conversation instead of meeting a stranger.
  #
  # Keyed on the playthrough rather than on the story: one generated world can
  # be played twice, and the second player has not had the first player's
  # conversation.
  def self.conversation_with(character, playthrough)
    return new(purpose: CHARACTER, character: character) if character.nil? || playthrough.nil?

    durable.find_or_initialize_by(playthrough: playthrough, character: character)
  end

  # Everything that is not the system instruction, oldest first. Ordered by id
  # rather than by `created_at`: two messages written in the same millisecond
  # are common and their order is the whole meaning of a conversation.
  def exchange_messages
    messages.where.not(role: "system").reorder(:id)
  end

  # TRIMS THE REPLAY so resuming a conversation cannot outgrow the context
  # window. Keeps the system instruction (a character sheet is not optional) and
  # the most recent `exchanges` worth of messages; deletes the rest.
  #
  # Deleting rather than merely not sending them is deliberate. RubyLLM's
  # `Chat#to_llm` rebuilds the request from every persisted message, so a chat
  # that keeps history it does not intend to send would send it. And the substance
  # is not lost: `Interaction` keeps every exchange this one ever had.
  #
  # Returns how many messages were dropped.
  def prune_history!(exchanges: HISTORY_EXCHANGES)
    keep = [ exchanges, 0 ].max * 2
    ids = exchange_messages.pluck(:id)
    doomed = ids[0...-keep] || []
    doomed = ids if keep.zero?
    return 0 if doomed.empty?

    messages.where(id: doomed).destroy_all.size
  end

  # What this conversation has cost, as far as the provider reported it.
  def input_tokens = messages.sum(:input_tokens)
  def output_tokens = messages.sum(:output_tokens)

  # Which model actually answered. The chat's own `model_id` is what it was
  # pointed at; this is what replied, which differs the moment `BaseAgent`
  # rotates past a model that failed.
  def answering_model_ids
    messages.where(role: "assistant").filter_map { |message| message.model&.model_id }.uniq
  end
end
