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
  # THIS PLAYTHROUGH'S OWN COPY OF THE WORLD'S THINGS -- every `Item` in the
  # playthrough layer, wherever it is in this game: in the party's hands, lying
  # in a room, or in one of the world's people's hands. Read through `#carried`,
  # `#items_lying_in` and `#items_held_by`, never through the association, so
  # each closed set has one query and one ordering.
  #
  # DESTROYED WITH THE PLAYTHROUGH, on the same reasoning as the chats: an
  # instance is this player's progress and nothing else's. The world's own rows
  # -- the templates these are copies of -- are untouched, which is the whole
  # point of the split: deleting a game cannot empty a room.
  has_many :items, dependent: :destroy
  # HOW MUCH IS LEFT OF EACH BODY THIS GAME HAS MET, one row per character.
  # Destroyed with the playthrough on the same reasoning as the chats and the
  # items: what has happened to somebody is this player's progress, and the
  # world's own `characters.hit_die` is untouched by it. Read through
  # `#vitals_for` and never through the association -- one reader, so the prompt,
  # the read-out and the sweep cannot come to disagree about a number.
  has_many :vitals, class_name: "Playthrough::Vitals", dependent: :destroy,
                    inverse_of: :playthrough
  # EVERY BLOW STRUCK IN THIS GAME, one row per round per attacker. Destroyed
  # with the playthrough on the same reasoning as the vitals: who swung at whom
  # is this player's progress, and `characters.hostile` -- the world's answer --
  # is untouched by it. Read through `Playthrough::Fight`, which is the one
  # thing that asks whether a fight is still on.
  has_many :blows, class_name: "Playthrough::Blow", dependent: :destroy,
                   inverse_of: :playthrough

  # WHAT THE WORLD ITSELF TOOK OFF THIS GAME'S BODY: one row per hazard paid,
  # and the `Playthrough::Blow` of a place. A separate table from the blows and
  # deliberately -- a hazard has no attacker and must never open a fight; see
  # `Playthrough::Toll`'s header. Read through `Playthrough::Moment` (which
  # states the untold ones to the prose) and by `rake game:mechanics`.
  has_many :tolls, class_name: "Playthrough::Toll", dependent: :destroy,
                   inverse_of: :playthrough

  # THE WORLD, COPIED INTO THIS GAME AS IT BEGINS: the story's starting
  # inventory into the party's own hands, and the room the player opens in.
  #
  # A copy rather than the rows themselves because the world layer has to stay
  # the world -- the file writes it, the exporter reads it back, the caps count
  # it, and a second player starting must not find the daybook already in
  # somebody else's hands or the opening room already emptied by somebody else's
  # game. See `Item::Snapshot`, which is the one writer of the playthrough layer.
  #
  # An after_create rather than a line in `PlaythroughsController#create`,
  # because three callers create playthroughs -- the controller, `rake
  # game:mechanics` and `EngineSweep::Walk` -- and a snapshot that only one of
  # them took would make the browser and the sweep test different games.
  after_create :take_up_the_opening_snapshot

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
  # THIS PLAYTHROUGH'S OWN ROWS, in the party's own hands -- an instance with no
  # room and no holder (`Item.in_hand`). Not `character.items`: that is what one
  # of the world's own people is holding, and for the protagonist it is the
  # story's STARTING INVENTORY, which is world data every game copies from.
  def carried
    Item.of_playthrough(self).in_hand.order(:id)
  end

  # WHAT IS LYING IN A ROOM, IN THIS GAME: the closed set `take` resolves
  # against, and the ONE reader of it. This playthrough's own instances and not
  # the world's templates, which is the whole of the captain's ruling of
  # 2026-09-04 -- what one party picks up off the floor is gone from ITS floor
  # and from nobody else's.
  #
  # It reads rather than writes: `Item::Snapshot` puts the copies there, at the
  # top of a turn and on arrival, so a read can never be the thing that changes
  # the world. A room this playthrough has never been in reads empty here, which
  # is honest -- it has not seen it yet.
  def items_lying_in(location)
    return Item.none if location.nil?

    Item.of_playthrough(self).lying_in(location).order(:id)
  end

  # WHAT ONE OF THE WORLD'S PEOPLE IS HOLDING, IN THIS GAME. The same statement
  # one place over, and it is a separate reader rather than an argument to the
  # one above because the two answer different closed sets: what is lying here
  # is takeable and what somebody is holding is not.
  def items_held_by(character)
    return Item.none if character.nil?

    Item.of_playthrough(self).for_character(character).order(:id)
  end

  # WHO THIS PARTY CAN SPEAK TO, TAKE A SWING AT, OR BE TOLD ABOUT, HERE, IN
  # THIS GAME -- and the ONE reader of it. The world says who is standing in the
  # room; this game says which of them can still answer.
  #
  # THE EXACT COUNTERPART OF `#items_lying_in`, and it is here for that method's
  # reason: `Character.present_in` is the WORLD's answer, and since a
  # playthrough can take somebody's last hit point the world's answer is no
  # longer this game's. Before this, `talk to Rowe` on a corpse resolved,
  # reached `InteractionAgent`, and the corpse answered -- which is the gap
  # `Item.lying_in` had before the item layers split, one table over.
  #
  # THE FOUR READERS COME THROUGH HERE: `Playthrough::Classifier#characters_here`
  # (so the closed set the model is offered holds nobody this game has killed),
  # `Playthrough::Moment#others` (so the prose is never told about somebody the
  # player then cannot speak to), `Playthrough::Turn#cast_of` (so a turn records
  # who was standing there in THIS game) and `Playthrough::Mechanics`'s `present`
  # line, through the classifier. `Character.present_in` stays exactly as it is
  # -- it is still the world's answer, and `Character::Registry`,
  # `EngineSweep::Invariants#cast_unmoved`, `Playthrough::Vitals::Snapshot` and
  # `rake game:doctor` all legitimately want it.
  #
  # A DEAD BODY IS STILL IN THE ROOM, in the world and on the record: nothing is
  # moved and `characters.location_id` is untouched. What changes is what the
  # closed sets OFFER this game.
  def cast_in(location)
    return [] if location.nil?

    Scene::Generator.characters_present(location).reject { |who| vitals_for(who)&.dead? }
  end

  # WHO IS FIGHTING THIS PARTY, HERE, IN THIS GAME -- and the ONE reader of it.
  #
  # TWO WAYS TO BE A FOE, AND THE SECOND IS THIS GAME'S OWN. The world says who
  # is hostile (`characters.hostile`, written by a seed file and by no model
  # ever); this game says who it has PROVOKED -- the captain's sixth ruling of
  # 2026-09-05, *"anyone can be attacked"*. Swing at the landlord and the
  # landlord fights back, in this playthrough and in no other, which is the
  # layer split doing exactly the work it was built for.
  #
  # It is the shape `#items_lying_in` has, one table over, and it is here for
  # that method's reason: `Character.hostile` is the WORLD's answer, and since a
  # playthrough can take somebody's last hit point the world's answer is no
  # longer this game's. A caller reading the scope alone would offer a corpse a
  # fight.
  #
  # `id`-ORDERED, because `#cast_in` is -- *"so two people in one room are
  # offered in a stable order"* -- and a fight has to be able to say who acts
  # when without inventing a second ordering (the captain's call C5: a round is
  # a turn, and the foes act in `id` order).
  #
  # THE PARTY IS NEVER IN IT, and it is excluded here rather than left to the
  # records to exclude. `#cast_in` reads `Scene::Generator.characters_present`,
  # which ADDS the protagonist and any companion to the room's own cast --
  # because the party is wherever the playthrough is and carries no whereabouts
  # at all -- and being struck marks a body provoked whoever struck it. Without
  # this line, one blow from a hound would put the player on the list of people
  # the hounds have to fight.
  #
  # An Array rather than a relation, because `#vitals_for` is a per-row question
  # and there is no SQL for it -- the same honest cost `#vitals_for` itself has.
  def foes_in(location)
    cast = cast_in(location)
    return [] if cast.empty?

    cast = cast.reject { |who| who.is_protagonist? || who.is_companion? }
    return [] if cast.empty?

    marks = vitals.where(character: cast).index_by(&:character_id)

    cast.select { |who| who.hostile? || marks[who.id]&.provoked? }
  end

  # WHETHER THIS GAME HAS PICKED A FIGHT WITH SOMEBODY, asked of one person.
  # `#foes_in` reads the same mark in one query for a whole room; this is for a
  # caller that has one name and wants one answer (`rake game:doctor`, the
  # mechanics read-out). Absent row means never provoked, which is the ordinary
  # state of everybody in every world -- the rule `Playthrough::Vitals` is
  # written under.
  def provoked?(character)
    return false if character.nil?

    vitals.find_by(character: character)&.provoked? || false
  end

  # HOW MUCH IS LEFT OF SOMEBODY, IN THIS GAME, AND THE ONE READER OF IT.
  #
  # `Playthrough::Moment`'s line to the narrator, the `rake game:mechanics`
  # read-out and `EngineSweep::Expectation`'s `hp:` all come through here, for
  # the same reason `#carried` is the one reader of the party's hands: a second
  # copy of the query is a second answer waiting to disagree.
  #
  # AN ABSENT ROW MEANS UNHURT, and this is the one place that rule is written.
  # Almost every person in a world is never touched, so a row per NPC per game
  # saying "nothing has happened" would be writing the default down -- see
  # `Playthrough::Vitals`. The answer is a `Condition` rather than the record, so
  # there is something to say either way and so a reader is handed no `update!`.
  #
  # NIL FOR SOMEBODY WITH NO STAT BLOCK, which is the honest nothing: there is
  # no maximum, so there is no condition to state. `rake game:doctor` reports
  # the person (`character_without_a_stat_block`) and every consumer here is
  # written to say nothing rather than to guess.
  def vitals_for(character)
    return nil if character.nil? || !character.stat_block?

    Playthrough::Vitals::Condition.for(character, vitals.find_by(character: character))
  end

  # THE PLAYER'S OWN CONDITION, which is the one the prose and the read-out are
  # about. Nil for a playthrough with no protagonist -- a world can be seeded
  # without one -- and then nothing anywhere says anything about a body.
  def condition = vitals_for(character)

  # WHETHER THIS GAME IS OVER, AND IT IS OVER FOR EXACTLY ONE REASON.
  #
  # The captain's ruling of 2026-09-04: *"zero hit points means death.
  # Playthrough is over and you can't do anything else. You have to start a new
  # playthrough."* `Playthrough::Turn#play` and `Playthrough::Mechanics#run` ask
  # this before anything else they do, so a line typed into a finished game
  # costs no model call and writes nothing at all.
  #
  # A COLUMN AND NOT A DERIVATION, though the protagonist's `hp_current` implies
  # it: the two are asked in different places for different reasons (this on
  # every turn, before the classifier; the condition when there is something to
  # say about a body), and a playthrough with no protagonist can still be handed
  # a `#end!` by a mechanic that has not been written yet. `rake game:doctor`
  # reports a disagreement rather than either half repairing the other silently.
  def over? = ended_at.present?

  # THE END, WRITTEN ONCE. `Playthrough::Turn#harm!` is the only caller, and it
  # calls it in the same statement that takes the last hit point.
  #
  # STORY TIME, NOT THE WALL CLOCK (AGENTS.md -> *Story time*): the playthrough
  # ended at the moment in the fiction the player died, which is where their own
  # clock stands. `Time.current` here would date a death rehearsed from a backup
  # to whenever the backup was opened.
  #
  # Idempotent: a game that is already over keeps the moment it ended at, so
  # nothing can quietly re-date a death.
  def end!(at: story_now)
    return self if over?

    update!(ended_at: at)
    self
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

  # THE SNAPSHOT A GAME OPENS ON: the story's starting inventory in the party's
  # hands, and the room the player is standing in.
  #
  # The room is snapshotted here as well as at the top of every turn because a
  # playthrough is looked at before it is played -- the play page renders the
  # opening arrival, and `Playthrough::Debug` prints the closed sets -- and a
  # first turn is not the first time somebody wants to know what is on the
  # floor. `Item::Snapshot`'s guard is per template, so doing it twice does
  # nothing the second time.
  #
  # `current_location` is nil for a playthrough whose room is assigned after
  # creation, which `EngineSweep::Walk` and `rake game:mechanics` both do; the
  # turn loop covers those.
  def take_up_the_opening_snapshot
    return if story.nil?

    snapshot = Playthrough::Snapshot.new(self)
    snapshot.of_the_party!
    snapshot.of_the_room!(current_location)
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
