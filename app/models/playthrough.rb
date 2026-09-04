# One browser session's progress through a story: which character the player is
# and where they are standing right now. The story itself stays on Story --
# this is the "someone playing it" half, so a single generated world can be
# played more than once.
class Playthrough < ApplicationRecord
  belongs_to :story
  belongs_to :character, optional: true
  belongs_to :current_location, class_name: "Location", optional: true
  belongs_to :current_scene, class_name: "Scene", optional: true

  # EVERY TURN THIS PLAYTHROUGH REACHED FOR SOMETHING THAT WAS NOT THERE.
  # The drift counter -- see Playthrough::Drift for what it measures and what
  # it deliberately does not claim.
  has_many :drifts, class_name: "Playthrough::Drift", dependent: :destroy,
                    inverse_of: :playthrough
  # EVERY TURN THIS PLAYTHROUGH ASKED FOR TWO THINGS AND GOT ONE. The opposite
  # shape to a drift -- everything named existed -- and counted apart from it
  # for that reason. See Playthrough::Overreach.
  has_many :overreaches, class_name: "Playthrough::Overreach", dependent: :destroy,
                         inverse_of: :playthrough
  # WHAT THE PLAYER THOUGHT OF EACH TURN -- one verdict per turn he judged, with
  # the turn's provenance frozen onto it. The evaluation instrument; see
  # Playthrough::Feedback for why it is a copy and not a reference.
  has_many :feedbacks, class_name: "Playthrough::Feedback", dependent: :destroy,
                       inverse_of: :playthrough
  # Every conversation this playthrough has had with a model. Destroyed with it:
  # they are this player's progress, not the world's -- see Chat.
  has_many :chats, dependent: :destroy
  # WHAT THIS PARTY IS CARRYING -- read through `#carried`, never through the
  # association, so the ordering and the one query live in one place.
  #
  # DESTROYED WITH THE PLAYTHROUGH, on the same reasoning as the chats: a
  # carried row is this player's progress. Putting them down instead would
  # leave a shared world littered with one daybook per deleted game, because a
  # copy of the starting inventory has no room it came from.
  has_many :items, dependent: :destroy

  # THE STORY'S STARTING INVENTORY, COPIED INTO THIS PLAYTHROUGH'S HANDS, and
  # the reason a new game does not open holding the last game's loot.
  #
  # A copy rather than the row itself because an `Item` is in exactly one place
  # and `Story#starting_inventory` has to stay world data -- the file writes it,
  # the exporter reads it back, and a second player starting must not find the
  # daybook already in somebody else's hands. Position needs no copy: a
  # Location holds two parties at once.
  #
  # An after_create rather than a line in `PlaythroughsController#create`,
  # because three callers create playthroughs -- the controller, `rake
  # game:mechanics` and `EngineSweep::Walk` -- and a starting inventory that
  # only one of them issued would make the browser and the sweep test different
  # games.
  after_create :take_up_the_starting_inventory

  # Generated at initialize rather than on create so the presence validation
  # below sees it. This is the only thing binding a browser session to a
  # playthrough, so it has to be unguessable.
  has_secure_token :token, length: 32, on: :initialize

  validates :token, presence: true, uniqueness: true
  validate :character_belongs_to_story
  validate :current_location_belongs_to_story
  validate :current_scene_belongs_to_story

  # WHAT THE PARTY IS CARRYING: the closed set `drop` resolves against, and the
  # ONE reader of it in the app. `Playthrough::Classifier#items_carried`,
  # `Playthrough::Moment#carried_names`, `Playthrough::Mechanics`'s `carrying`
  # line and the debug page all come through here, for the same reason
  # `Scene::Generator.characters_present` is the one reader of who is in a room:
  # a second copy of the query is a second answer waiting to disagree.
  #
  # Not `character.items`. That is what one of the world's own people is
  # holding, and for the protagonist it is the story's starting inventory --
  # shared by every playthrough, which is the defect this column closes.
  def carried
    Item.carried_by(self).order(:id)
  end

  # WHERE THIS PLAYTHROUGH STANDS ON THE STORY'S CLOCK -- the moment the player
  # is living in, which is the moment their last scene happened at.
  #
  # Per-playthrough rather than `Story#clock`, and the difference matters as
  # soon as one world is played twice: the story's clock is the high-water mark
  # across every playthrough, because the world moves for everybody, but a
  # player's own next turn follows on from THEIR last turn.
  def story_now
    current_scene&.story_timestamp || story.clock
  end

  # THIS PLAYTHROUGH'S TURNS, oldest first.
  #
  # Scenes are a `previous_scene` linked list, so walking BACKWARDS from
  # `current_scene` gives this playthrough's turns and nobody else's -- every
  # playthrough of a story starts on the same opening arrival, so the forward
  # direction stopped being single-valued (see `Scene#next_scenes`).
  #
  # It lives here rather than in a controller because two readers need the same
  # answer: the play page's turn log and `Playthrough::Debug`. A debug view that
  # walked the chain itself could disagree with the prose about which turns
  # belong to this playthrough, which is the one thing it must never do.
  def scene_chain
    scenes = []
    scene = current_scene

    while scene
      scenes.unshift(scene)
      scene = scene.previous_scene
    end

    scenes
  end

  # The story time a turn of `kind` ends at: now, plus what that kind of turn
  # costs from `Scene::TURN_MINUTES`. Journeys are not in that table -- an
  # arrival costs the edge it walked, which `Scene::Generator` works out.
  def story_time_after(kind)
    story_now + Scene::TURN_MINUTES.fetch(kind).minutes
  end

  # THE TURN LOG the play page reads: `scene_chain`, with what the turn partial
  # needs preloaded.
  #
  # It is a model method rather than a controller one because a third reader
  # turned up: `NarrationJob` renders this same log when it broadcasts a finished
  # turn, and a job has no controller to borrow a private method from. The walk
  # itself stays in `scene_chain`, shared with `Playthrough::Debug`, so the debug
  # view and the prose cannot disagree about whose turns these are.
  #
  # `interactions` is preloaded because the turn partial reads it on every scene
  # to name who the player was talking to, and all but the talk turns have none.
  def turn_log
    scenes = scene_chain

    ActiveRecord::Associations::Preloader.new(
      records: scenes, associations: { interactions: :character }
    ).call

    scenes
  end

  # THE VERDICT ON EACH TURN, KEYED BY THE TURN, for the log to render the
  # controls in the state the records already hold.
  #
  # One query for the whole log rather than a lookup per entry: the log is the
  # entire playthrough and the partial asks about every turn in it. It is a plain
  # read of this playthrough's own rows -- a verdict is per (playthrough, scene)
  # because a story's opening arrival is shared by every playthrough of it, so
  # keying on the scene alone would show one player another player's judgement.
  def feedback_by_scene
    feedbacks.index_by(&:scene_id)
  end

  # The ways out of where the player is standing -- the move targets
  # `Playthrough::Classifier` will accept, which is why the play page prints
  # them rather than leaving the player to guess.
  def exits
    current_location&.exits&.order(:id) || Location.none
  end

  # HOW MUCH OF THE PLAYTHROUGH A PROMPT IS ALLOWED TO CARRY, in characters.
  #
  # 600 is roughly 150 tokens, and it is chosen against what it replaces rather
  # than out of the air: the narrator prompt used to carry the previous scene's
  # full description and nothing else, which is ~500 characters for one turn of
  # memory. The same budget spent on `scenes.summary` buys four or five turns,
  # because a summary is the same moment in a fifth of the words. That is the
  # whole trade -- more memory, the same prompt.
  RECAP_BUDGET = 600

  # HOW MANY TURNS BACK IT WILL EVEN LOOK. The budget is the real limit; this
  # keeps a long playthrough from loading two hundred scenes to throw away all
  # but five of them.
  RECAP_SCENES = 12

  # WHAT HAS HAPPENED SO FAR, short enough to put in a prompt.
  #
  # Built out of `scenes.summary` -- the column `Scene::Generator` has been
  # writing on every arrival all along, for exactly this. Nothing new is
  # generated and no model is asked anything: summarising happens once, when the
  # arrival is written, and this is where it is finally spent.
  #
  # Newest first, oldest dropped when the budget runs out, and the drop is
  # STATED rather than silent -- a prompt that quietly forgets is worse than one
  # that says it has forgotten. `before` excludes the scene the caller is already
  # putting in the prompt in full, so the recap never repeats it.
  #
  # A scene with no summary contributes its first sentence. Only an arrival is
  # summarised by the model; a narrated turn is not, and truncating what it wrote
  # is honest where inventing a summary would cost a call per turn.
  def recap(before: current_scene, budget: RECAP_BUDGET, scenes: RECAP_SCENES)
    chain = scene_chain
    chain = chain[0...chain.index(before)] if before && chain.index(before)
    candidates = chain.last(scenes).reverse

    lines = []
    room = budget
    dropped = 0

    candidates.each do |scene|
      line = Scene.recap_line(scene)
      next if line.blank?

      if line.length > room
        dropped += 1
        next
      end

      room -= line.length
      lines << line
    end

    return nil if lines.empty?

    text = lines.reverse.join("\n")
    dropped.positive? ? "(#{dropped} earlier turn#{"s" unless dropped == 1} left out)\n#{text}" : text
  end

  # DROPS THE CONVERSATION AUDIT TRAIL OLDER THAN THE LAST `keep` TURNS --
  # WHICH, BY DEFAULT, IS NOTHING AT ALL.
  #
  # `keep` is nil unless somebody set `TA_CHAT_KEEP_TURNS`, and nil means keep
  # everything: this returns 0 without touching a row. The reasoning that used
  # to live here -- a SQLite file on a laptop, several KB a turn, the biggest
  # thing a long game accumulates -- was true in every clause and wrong in its
  # conclusion. `Chat::KEEP_TURNS` carries the measurement that replaced it.
  #
  # THE PATH IS KEPT rather than deleted because the cap is still opt-in: this
  # is an open-source app that gets installed on strangers' machines, and an
  # escape hatch for anybody who wants a bounded file costs one guard clause.
  #
  # The DURABLE conversations are never pruned here: they are trimmed message by
  # message when they are picked up (Chat#prune_history!), because they are the
  # one kind the game does read back. Deleting one would give a character
  # amnesia; deleting an old classifier exchange loses nothing but a receipt.
  #
  # Returns how many chats were deleted.
  def prune_conversations!(keep: Chat::KEEP_TURNS)
    return 0 if keep.nil?

    recent = scene_chain.last([ keep, 0 ].max).map(&:id)

    chats.one_shot
         # Attributed to some turn -- a chat whose messages carry no scene yet
         # belongs to a turn still being played, or to one that failed before it
         # produced a scene, and neither is old.
         .where(id: Message.where.not(scene_id: nil).select(:chat_id))
         .where.not(id: Message.where(scene_id: recent).select(:chat_id))
         .destroy_all.size
  end

  private

  # One row per thing the story starts the player with. Skipped when this
  # playthrough already carries something, so re-running it -- or creating a
  # playthrough with items already attached, as a test fixture may -- cannot
  # hand out the kit twice.
  #
  # `properties` is copied with the rest: a copy of a thing is that thing, and
  # a daybook with no page count is a different object from the one the file
  # describes.
  def take_up_the_starting_inventory
    return if story.nil? || items.exists?

    story.starting_inventory.each do |original|
      items.create!(name: original.name, description: original.description,
                    properties: original.properties)
    end
  end

  # The character, location and scene are all facets of one story; pointing at
  # another story's records would silently mix two worlds together.
  def character_belongs_to_story
    return if character.nil? || story.nil?
    return if character.story_id == story_id

    errors.add(:character, "must belong to the playthrough's story")
  end

  def current_location_belongs_to_story
    return if current_location.nil? || story.nil?
    return if current_location.story_id == story_id

    errors.add(:current_location, "must belong to the playthrough's story")
  end

  def current_scene_belongs_to_story
    return if current_scene.nil? || story.nil?
    return if current_scene.story_id == story_id

    errors.add(:current_scene, "must belong to the playthrough's story")
  end
end
