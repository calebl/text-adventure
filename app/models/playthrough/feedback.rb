# ONE JUDGEMENT OF ONE TURN, recorded by the person playing it.
#
# AN EVALUATION INSTRUMENT, and that decides every part of its shape. Two open
# questions -- which model should narrate the world (`ta-narrator-model`) and
# which should write conversation (`ta-talk-model`) -- are otherwise answered by
# blind reads of generated passages. A verdict attached to a real turn during
# real play is better evidence than any of those, and unlike a blind read it
# accumulates for free while the game is being played anyway.
#
# So it is built for two things at once and they pull in opposite directions:
# LOW FRICTION WHILE PLAYING (one click for a verdict, the note optional -- a
# verdict that needs an essay attached will not get recorded at all) and RICH
# ENOUGH AFTERWARDS to answer "which model do the turns I marked good actually
# come from" without a console. The second is what the frozen columns are for.
#
# WHY THE PROVENANCE IS FROZEN AND NOT REFERENCED. `Chat#answering_model_ids` is
# the honest answer to which model replied -- including after `BaseAgent` rotated
# past one that failed, which is exactly the case worth measuring -- but the
# conversations it reads can be destroyed by `Playthrough#prune_conversations!`
# whenever `TA_CHAT_KEEP_TURNS` sets a cap. The default now keeps them, and that
# does NOT make this copy redundant -- it makes it belt and braces. An install
# that opts into a bounded file must not silently lose its evaluation record on
# precisely the old turns a long session produces most of, and a verdict holding
# a reference would. It takes a COPY instead, once, when it is recorded.
#
# WHAT IS FROZEN, AND WHAT IS NOT:
#
#   frozen      `prose_model`, `prose_models`, `prose_purpose`,
#               `answering_models`, `input_tokens`, `output_tokens` -- all of it
#               read out of `chats` / `messages`, all of it destroyed by the
#               pruner.
#   referenced  the `Scene`: its `description` (the prose being judged), its
#               `typed` (the player's own words, a column since
#               `Playthrough::Turn#play` started writing it), its
#               `story_timestamp` and its location. None of that is pruned, and
#               a copy would be a second answer that could disagree.
#   derived     which branch the turn took. `Playthrough::Debug#branch_for`
#               reads it off the durable records -- `is_opening`, an
#               `Interaction`, a change of location -- so freezing it here would
#               duplicate a reading the debug view already owns.
#
# AMENDABLE, because he will change his mind about a turn once the next one
# lands. `.record` upserts on (playthrough, scene) and the frozen columns are
# written ONLY on create: the provenance describes the turn, not the verdict, so
# amending a verdict must not re-snapshot against receipts that have since been
# pruned.
class Playthrough::Feedback < ApplicationRecord
  # THE VERDICTS, as a fixed table in code rather than free text -- the same
  # reason `Playthrough::Drift::ACTIONS` and `LocationConnection::DISTANCES` are
  # fixed tables. Three, ordinal, one word each, in order from best to worst so
  # a reader (and a later comparison) has an ordering without inventing one.
  #
  # THREE AND NOT MORE. The axis being measured is how good the prose is, and
  # mid-play there is no room for a taxonomy: a fourth button is a decision to
  # make instead of a judgement to record. Everything that is not this axis
  # already has somewhere better to go -- narration that contradicts the records
  # is `Story::Audit`, a reach that resolved to nothing is `Playthrough::Drift`
  # -- and anything else goes in the note.
  VERDICTS = %w[good weak bad].freeze

  # WHICH CONVERSATIONS PRODUCE THE PROSE THE PLAYER READS.
  #
  # `narration` is `Scene::Narrator` answering what was typed,
  # `interaction-narration` is `InteractionAgent`'s second pass turning a
  # character's reaction into prose, and `arrival` is `Scene::Generator`
  # narrating walking into a place. Those are the three calls on the prose side
  # of the line AGENTS.md draws -- prose the player watches arrive, as against
  # anything that fills a record.
  #
  # The other purposes are deliberately absent: `classifier` picks from a closed
  # set, `character` fills in `Interaction`'s five fields, and `location`
  # realizes a room the arrival then narrates -- none of them wrote the words
  # being judged. They are still counted in `answering_models` and in the token
  # totals, which is the whole reason that column is a list.
  #
  # A set rather than an ordering: when a turn holds two of these, the prose the
  # player read is the one written LAST, which `provenance_for` reads off the
  # message ids rather than off this array.
  PROSE_PURPOSES = %w[narration interaction-narration arrival].freeze

  belongs_to :playthrough
  belongs_to :scene

  validates :verdict, presence: true, inclusion: { in: VERDICTS }
  validates :scene_id, uniqueness: { scope: :playthrough_id }
  validate :scene_belongs_to_playthrough

  scope :in_story_order, -> { joins(:scene).order("scenes.story_timestamp", "scenes.id") }
  scope :for_verdict, ->(verdict) { where(verdict: verdict.to_s) }

  # RECORDS OR AMENDS THE VERDICT ON ONE TURN, and freezes the turn's provenance
  # the first time.
  #
  # The upsert is the amendment: he clicks `weak` on a turn he called `good`
  # two turns ago and the same row changes, because a verdict per turn is what
  # the whole instrument is. Only `verdict` and `note` are ever rewritten --
  # `provenance_for` is read once, on create, while the receipts still exist.
  #
  # `note` is left ALONE when it is not supplied, so clicking a different
  # verdict does not silently throw away the reason he typed for the old one.
  # Passing an empty string is how a note is cleared.
  def self.record(playthrough:, scene:, verdict:, note: nil)
    feedback = find_or_initialize_by(playthrough: playthrough, scene: scene)
    feedback.assign_attributes(provenance_for(scene)) unless feedback.persisted?
    feedback.verdict = verdict.to_s
    feedback.note = note.to_s.strip.presence unless note.nil?
    feedback.save!
    feedback
  end

  # THE RECEIPTS FOR ONE TURN, as the five values worth keeping past the pruner.
  #
  # Read from `messages.scene_id`, which is how a turn's cost is totalled
  # everywhere else in the app (see `Chat` and `BaseAgent#attribute_to!`): a
  # durable conversation with a character spans many turns, so the turn is
  # recorded on the message and never on the chat.
  #
  # Every value here can honestly be nil or zero, and the two are not the same
  # thing. An opening arrival was generated when the world was built and has no
  # receipts of its own; a turn pruned under a `Chat::KEEP_TURNS` cap had them
  # and lost them. `#receipts_kept?` tells a reader which of those they are
  # looking at, and the view says so rather than showing a blank.
  def self.provenance_for(scene)
    messages = scene.messages.includes(:model, :chat).sort_by(&:id)
    answered = messages.select { |message| message.role.to_s == "assistant" }
    prose = answered.select { |message| PROSE_PURPOSES.include?(message.chat&.purpose) }
    # The LAST prose answer on the turn, because an arrival realizes the room
    # before it narrates arriving in it and only the second one is read -- and
    # because a rotation leaves the kept answer last.
    kept = prose.last

    {
      prose_model: kept&.model&.model_id,
      prose_purpose: kept&.chat&.purpose,
      prose_models: model_ids(prose),
      answering_models: model_ids(answered),
      input_tokens: messages.sum { |message| message.input_tokens.to_i },
      output_tokens: messages.sum { |message| message.output_tokens.to_i }
    }
  end

  # A joined list rather than a JSON column, the way `Playthrough::Drift#offered`
  # keeps the set that was on the table: this is read by a person and grouped in
  # Ruby, and `#answering_model_ids` is the inverse.
  def self.model_ids(messages)
    messages.filter_map { |message| message.model&.model_id }.uniq.join(", ")
  end
  private_class_method :model_ids

  # WHETHER THE TURN STILL HAD ITS RECEIPTS when this was recorded. False means
  # the verdict stands but the provenance does not -- the conversations had
  # already been pruned, or the `Scene` was written by something other than the
  # loop -- and that is reported rather than shown as a turn that cost nothing.
  def receipts_kept? = prose_model.present? || answering_models.present?

  # Every model that answered anything on the turn, as the list it was.
  def answering_model_ids
    answering_models.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  # Every model that attempted the PROSE, as the list it was. `prose_model` is
  # the last of them.
  def prose_model_ids
    prose_models.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  # WHETHER THE PROSE ITSELF HAD MORE THAN ONE MODEL BEHIND IT -- `BaseAgent`
  # rotated on the call being judged, past a model that failed or a refusal it
  # would not write. Worth seeing next to a verdict: prose that took two
  # attempts is not clean evidence about either model on its own.
  #
  # Read off `prose_models` and NOT `answering_models`, which is the whole
  # reason there are two lists. A turn whose classifier rotated while its
  # narration answered first time is not a turn whose prose rotated, and saying
  # it was would flag the verdict for something that happened somewhere else.
  def rotated? = prose_model_ids.size > 1

  # Where the turn sits on the story's clock, read through the Scene rather than
  # copied. Story time, never the wall clock -- see AGENTS.md.
  def story_timestamp = scene&.story_timestamp

  # What the player typed to cause the turn being judged. `Scene#typed` is a
  # column and survives the pruner, which is what makes a verdict legible at
  # all: a judgement of prose with no sight of the prompt that asked for it is
  # half a record. Nil on an opening arrival, which nobody typed for.
  def typed = scene&.typed

  private

  # A verdict on a scene from another world is two worlds mixed together, which
  # is the same objection `Playthrough#current_scene_belongs_to_story` makes and
  # is written the same way.
  #
  # It stops at the story rather than at the chain on purpose. The exact set of
  # turns is `Playthrough#scene_chain`, and `FeedbacksController` resolves
  # against it -- the app closing a set and acting on the resolved record, as
  # everywhere else here. Repeating that walk in a validation would cost a query
  # per link on every save to re-answer a question the caller already answered.
  def scene_belongs_to_playthrough
    return if scene.nil? || playthrough.nil?
    return if scene.story_id == playthrough.story_id

    errors.add(:scene, "must be a turn in the playthrough's story")
  end
end
