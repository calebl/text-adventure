class Scene < ApplicationRecord
  # THE READERS THAT WRITE A TURN, which is `Playthrough::Grammar::PATHS` minus
  # `engine_view`: `harm`, `check` and the read-outs write no `Scene` at all, so
  # a scene carrying that value is a defect and `rake game:doctor` names it
  # (`scene_with_an_unknown_reader`). The VALIDATION stays on the whole of
  # `PATHS` -- one vocabulary for the column -- and this is what the doctor
  # measures against, because the two questions are different: what the column
  # may hold, and what a turn can honestly say.
  TURN_READERS = (Playthrough::Grammar::PATHS - [ "engine_view" ]).freeze

  # WHAT A TURN CAN HAVE DONE, and it is deliberately WIDER than what a player
  # can have asked for. `Playthrough::IntentSchema::INTENTS` is the closed enum
  # on a MODEL CALL; this is the closed list of things the ENGINE does to the
  # world. They were one list while every act was a player intent, and a fight
  # is the first act the engine takes that no typed word names -- so the record
  # grows here and the prompt does not.
  #
  # `attack`, `hazard` and `throw` are in the list before anything writes one:
  # the column is what says a fight is recordable, and decoupling it from the
  # classifier's enum is the change that has to land before any of that can be
  # written down. Nothing here widens `INTENTS`, and nothing here reaches a
  # prompt. `#engine_authored?` is the difference between the two lists, asked
  # as a question.
  ACTIONS = (Playthrough::IntentSchema::INTENTS + %w[attack hazard throw]).freeze

  # AND WHICH OF THOSE THE ENGINE WROTE THE WORDS OF, which is a DIFFERENT
  # question from which of them a player can type -- and it used to be answered
  # as though it were the same one.
  #
  # `#engine_authored?` was the difference between `ACTIONS` and `INTENTS`, and
  # that was exactly right while every act outside the closed enum also carried
  # the engine's own sentence: `Playthrough::Fight#close!` writes a fight's
  # description itself and a hazard will write its own. A THROW DOES NOT. It is
  # an act no typed word in the enum names, so it lives in `ACTIONS` -- and its
  # `Scene` is ordinary NARRATION, streamed by `Scene::Narrator` off
  # `Playthrough::Turn#thrown_fact` exactly as a `take`'s is. Left in the
  # difference it would have been skipped by `Story::Audit` and
  # `Eval::Richness` and counted in `Story::Scoreboard#excluded`, which is real
  # prose going unchecked and a denominator quietly shrinking.
  #
  # So the list is POSITIVE now: what the engine authored is named here rather
  # than inferred from what a prompt may ask for. `attack` and `hazard` keep
  # exactly the answer they had.
  ENGINE_AUTHORED = %w[attack hazard].freeze

  # How much STORY time a turn costs when it is not a journey. A fixed table in
  # code, for exactly the reason `LocationConnection::DISTANCES` is one: how
  # long something takes in the fiction is the app's to decide, so it is a
  # lookup rather than a number a narrator produced or the wall clock supplied.
  # A journey is the one turn that is not in here -- it costs
  # `LocationConnection.travel_minutes` for the edge actually walked.
  TURN_MINUTES = {
    # Standing and talking to somebody.
    "conversation" => 10,
    # Looking at, trying, picking up: one beat in the room.
    "action" => 5
  }.freeze

  belongs_to :story
  belongs_to :location
  belongs_to :previous_scene, class_name: "Scene", optional: true
  # PLURAL, and that is the whole of the fix. This used to be a `has_one
  # :next_scene` over what is now a branch point: the story's opening arrival
  # belongs to the world, so every playthrough of that story starts on the same
  # Scene and every one of their first moves links back to it. A `has_one` there
  # does not fail -- it silently returns whichever playthrough's turn came back
  # first, which is a wrong answer dressed as a right one.
  #
  # Walking BACKWARDS from a playthrough's `current_scene` stays unambiguous, so
  # the turn log (`Playthrough#turn_log`) was never affected and is
  # not changed by this. Nothing in `app/` reads the forward direction at all;
  # it is kept, plural and nullifying, because destroying a scene otherwise
  # leaves its successors pointing at a row that is gone.
  has_many :next_scenes, class_name: "Scene", foreign_key: "previous_scene_id",
                         dependent: :nullify, inverse_of: :previous_scene
  has_and_belongs_to_many :characters
  # What a character thought and felt during this moment. Written by the talk
  # branch of the game loop; nullified rather than destroyed because an
  # Interaction belongs to its character first and the scene only optionally.
  has_many :interactions, dependent: :nullify
  has_many :playthroughs, foreign_key: :current_scene_id, dependent: :nullify, inverse_of: :current_scene
  # Turns on which the player, having read THIS narration, reached for something
  # the records do not have. NULLIFIED rather than destroyed: the drift is the
  # measurement and the scene is only the suspect -- losing the prose must not
  # lose the count. See Playthrough::Drift.
  has_many :drifts, class_name: "Playthrough::Drift", dependent: :nullify,
                    inverse_of: :scene
  # THE BLOWS THIS SCENE CLOSED A FIGHT OVER. NULLIFIED rather than destroyed,
  # on exactly the drift's reasoning one line up: the blow is the durable record
  # of the round and this Scene is only the sentence about it, so losing the
  # sentence must not lose what the dice did. A blow with no scene reads as an
  # OPEN fight (`Playthrough::Blow.open`), which after the scene is gone is the
  # truth about it -- nothing has closed it. See `Playthrough::Fight`.
  has_many :blows, class_name: "Playthrough::Blow", dependent: :nullify,
                   inverse_of: :scene
  # THE HAZARDS THIS SCENE'S PROSE CARRIED. NULLIFIED, on the blows' reasoning
  # one line up: the toll is what the dice did and this Scene is only the
  # paragraph that mentioned it. A toll with no scene reads as UNTOLD, which
  # after the paragraph is gone is the truth about it -- nothing has said it.
  has_many :tolls, class_name: "Playthrough::Toll", dependent: :nullify,
                   inverse_of: :scene
  # Judgements the player recorded on this turn. DESTROYED rather than nullified,
  # which is the opposite of the drift above it and for a reason: a drift is the
  # measurement and the scene is only the suspect, whereas a verdict is a
  # judgement OF this prose and means nothing once the prose is gone.
  has_many :feedbacks, class_name: "Playthrough::Feedback", dependent: :destroy,
                       inverse_of: :scene
  # Every message exchanged with a model on this turn -- the prompts that were
  # sent, the answers that came back, what they cost and which model wrote them.
  # Nullified rather than destroyed: a message belongs to its `Chat` first, and
  # deleting a scene should not tear a hole in a conversation.
  has_many :messages, dependent: :nullify

  # WHAT THE TURN DID, and to which record. Written by
  # `Playthrough::Turn#play` on every branch, beside `typed`.
  #
  # Polymorphic because the closed set `Playthrough::Classifier` resolves
  # against is already three kinds of record -- an exit, somebody standing
  # here, a thing on the floor or in the player's hands -- and one reference
  # that says which kind it was is honest where three nullable columns and a
  # rule about which is set would not be.
  #
  # OPTIONAL, and nil is three different things told apart by `resolved_action`:
  # no action at all (an opening arrival, or a turn written before this column
  # existed), or an action that resolved to no record -- which is drift, and is
  # counted by `Playthrough::Drift` rather than left to be inferred here.
  belongs_to :acted_on, polymorphic: true, optional: true

  # WHICH READER ANSWERED THE LINE THIS TURN CAME OUT OF -- one of
  # `Playthrough::Grammar::PATHS`, written by `Playthrough::Turn#play` beside
  # `typed` and `resolved_action`, in the one place that has the command and the
  # scene on every branch.
  #
  # THE CAPTAIN'S RULING OF 2026-09-04, EVENING made it a question worth
  # recording: *"support a slash prefix autocomplete in the text box, and
  # resolve those and verb-prefixed lines offline then fallback to the model."*
  # Two readers now answer the lines one reader used to, and a miss attributed
  # to "the classifier" that the classifier never saw would send the next prompt
  # change at the wrong thing. `Playthrough::Drift` and `Playthrough::Overreach`
  # are written from inside `Playthrough::Classifier#classify`, so they are
  # already `model`-only by construction; this is what says so on the turn, and
  # what lets `rake game:score` and `Eval::Classifier` size their denominators.
  #
  # `engine_view` is in the closed list and NO SCENE CARRIES IT: `harm`, `check`
  # and the read-outs are `Playthrough::Mechanics`'s own instruments and write no
  # `Scene` at all. It is in the list because the list is one vocabulary for both
  # readers and both consumers, and `rake game:doctor` is what would name a row
  # that somehow got one.
  #
  # NULLABLE, AND NIL IS TWO THINGS: an opening arrival, which nobody typed and
  # no reader read, and a turn played before the column existed -- which is
  # every turn in the captain's database and in every stored `rake eval:run` set.
  # `Update::Steps::StampResolvedBy` stamps the second, because before this
  # column there was exactly one reader; an opening arrival keeps nil for ever.
  # Read it through `#resolved_by_reader` for the same reason `#recorded_action`
  # exists: an older run's `scenes` table has no such column at all.

  # WHAT THE PLAYER TYPED TO CAUSE THIS TURN, on every branch. `typed` is
  # nil only for a `Scene` nobody asked for: the opening arrival, which is
  # world data written before anybody plays.
  #
  # It is a column rather than something reconstructed because the
  # reconstruction did not last. `Interaction#user_input` only exists on the
  # talk branch, and the classifier's stored prompt -- where the debug view read
  # it from -- can be pruned as the playthrough runs (Chat::KEEP_TURNS, opt-in
  # now but the default then), so the player's own words vanished from older
  # turns. This column does not depend on that setting. Written by
  # `Playthrough::Turn#play`.
  validates :description, presence: true
  validates :story_timestamp, presence: true
  # `Scene::ACTIONS` and NOT `Playthrough::IntentSchema::INTENTS`: what the
  # engine may record is wider than what the classifier may be offered -- see
  # the constant's note. Not an `enum` because `Scene.take` is already an
  # ActiveRecord finder, so an enum named for one of these actions would
  # quietly redefine it.
  validates :resolved_action, inclusion: { in: ACTIONS }, allow_nil: true
  # WHICH READER ANSWERED THE LINE, out of the class that owns the two readers.
  # A string and not an enum for the same reason above, and `allow_nil` for a
  # different one: see `#resolved_by`'s note below.
  validates :resolved_by, inclusion: { in: Playthrough::Grammar::PATHS }, allow_nil: true
  validate :single_opening_scene_per_story

  after_create :mark_location_visit

  scope :openings, -> { where(is_opening: true) }

  # WHETHER THERE IS A TURN BEFORE THIS ONE to compare against. Several checks
  # in `Story::Audit` are differences -- did the location change, did anything
  # happen since -- and a difference needs two terms, so a scene at the head of
  # a chain is outside their denominator rather than clean by them.
  # `Story::Scoreboard` reads it to size each check's denominator honestly, and
  # `Story::Scoreboard::Corpus::Passage` answers the same question.
  def follows_a_turn? = previous_scene_id.present?

  # WHAT THIS TURN DID, asked the way a check asks it. `took?` and `dropped?`
  # are the two transitions the app owns outright -- the row moved before any
  # prose existed (`Playthrough::Turn#take_item`, `#drop_item`) -- so a scene
  # that answers `true` to either is a scene whose state change is not in
  # question. `Story::Audit` reads them; nothing else needs to.
  #
  # Both require the record as well as the label, because an action that
  # resolved to nothing moved nothing.
  def took? = recorded_action == "take" && acted_on_record.is_a?(Item)

  def dropped? = recorded_action == "drop" && acted_on_record.is_a?(Item)

  def moved_to? = recorded_action == "move" && acted_on_record.is_a?(Location)

  # WHETHER THE ENGINE, RATHER THAN A NARRATOR, WROTE THIS ROW'S DESCRIPTION.
  # One of `ENGINE_AUTHORED`, and read off that list rather than derived from
  # the gap between `ACTIONS` and `INTENTS` -- see the constant for why a throw
  # is in the gap and is not engine copy. False for a turn with no action on
  # record at all: an opening arrival is prose somebody generated.
  def engine_authored?
    ENGINE_AUTHORED.include?(recorded_action.to_s)
  end

  # THE TWO COLUMNS, READ SAFELY, AND THE READERS EVERYTHING ELSE HERE USES.
  #
  # `has_attribute?` rather than a nil check, and it is not defensive dressing:
  # a `Scene` does not always come from this app's database. `rake eval:score`
  # and `rake eval:read` open the SQLite file one generated run left behind,
  # and every set swept before this migration has a `scenes` table with no such
  # column at all. Reading it there raises; asking whether the row carries it
  # answers `false`, which is the truth about that run -- it did not record
  # what its turns did. Nothing else in the sweep changes.
  def recorded_action = has_attribute?("resolved_action") ? resolved_action : nil

  def acted_on_record = has_attribute?("acted_on_type") ? acted_on : nil

  # Nil for a scene out of a database whose `scenes` table predates the column,
  # which is every set `rake eval:score` opens from before 2026-09-05 -- the
  # truth about that run rather than a raise.
  def resolved_by_reader = has_attribute?("resolved_by") ? resolved_by : nil

  # HOW THE TURN READ, in one line, for a person: `rake eval:read` and the debug
  # page print it beside what was typed. Nil for a turn with no action on
  # record, which reads as absent rather than as "other -> nothing".
  def resolution
    return nil if recorded_action.blank?

    "#{recorded_action} -> #{acted_on_label || "nothing"}"
  end

  # A record as the player would have typed it -- `fullname` for a person,
  # `name` for a place or a thing. The same two names the closed enum the
  # classifier answered from was built out of.
  def acted_on_label
    record = acted_on_record
    return nil if record.nil?

    record.respond_to?(:fullname) ? record.fullname : record.name
  end

  # ONE LINE OF MEMORY for a past turn, for `Playthrough#recap`.
  #
  # `summary` first, because it is what the model was asked for and paid for on
  # every arrival -- the same moment in a fifth of the words. A narrated turn has
  # none (Scene::Narrator streams unschema'd prose and cannot produce a second
  # field), so it contributes its own opening sentence instead. Truncating what
  # was written is honest; asking a model to summarise it would put a second
  # call on every turn, which is exactly the cost this is here to avoid.
  def self.recap_line(scene)
    return nil if scene.nil?
    return scene.summary.strip if scene.summary.present?

    scene.description.to_s.strip.split(/(?<=[.!?])\s+/).first.to_s.truncate(200).presence
  end

  private

  # Arriving somewhere is what puts the protagonist in a room, and the stamp is
  # what makes walking back in later read as coming back rather than as finding
  # (Scene::Generator, Location#time_since_last_visit).
  #
  # Stamped with this scene's OWN `story_timestamp` rather than with
  # `Time.current`: the visit happened at the moment in the story that the scene
  # happened at, and that is what makes "you were last here about an hour ago"
  # mean an hour of the story rather than an hour of somebody's afternoon.
  #
  # The opening arrival is the exception, and it has to be. It is world data:
  # generated once when the world is built and loaded out of a seed file, which
  # can be days or months before anybody plays. Stamping the visit then would
  # tell the first player who walks back into the opening room that they were
  # gone for however long the file has been on disk. Nobody was there. The
  # protagonist arrives when a playthrough starts, and that is where the stamp
  # belongs -- PlaythroughsController#create writes it.
  def mark_location_visit
    return if is_opening?

    location.mark_protagonist_visit!(story_timestamp)
  end

  # A story opens once. `is_opening` is also the natural key WorldSeed::Loader
  # matches an opening arrival on, so a second one would make the seed load
  # ambiguous as well as the fiction.
  def single_opening_scene_per_story
    return unless is_opening?
    return if story_id.nil?

    conflict = Scene.where(story_id: story_id, is_opening: true)
    conflict = conflict.where.not(id: id) if persisted?
    return unless conflict.exists?

    errors.add(:is_opening, "is already set on another scene in this story")
  end
end
