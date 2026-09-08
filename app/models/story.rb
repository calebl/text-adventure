class Story < ApplicationRecord
  belongs_to :universe
  has_many :characters, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :scenes, dependent: :destroy
  # Interactions hang off characters; destroying the story destroys the
  # characters, which take their own interactions with them.
  has_many :interactions, through: :characters
  has_many :playthroughs, dependent: :destroy
  has_one :protagonist, -> { where(is_protagonist: true) }, class_name: "Character", inverse_of: :story
  # The arrival that opens the story, and the one Scene that is part of the
  # WORLD rather than part of somebody's progress through it. Generated once by
  # `rake game:new`, carried in db/seeds/worlds/*.yml, and shared by every
  # playthrough: they all start standing in it. Nil for a story built before
  # opening arrivals existed, which PlaythroughsController falls back for.
  has_one :opening_scene, -> { where(is_opening: true) }, class_name: "Scene", inverse_of: :story
  # The laws of this world that the APP enforces, on this story's own clock.
  # Parameters of the world, so they are exported and seeded with it.
  has_many :world_mechanics, dependent: :destroy
  has_many :world_events, dependent: :destroy
  # WHERE THIS WORLD IS GOING. The arc and its beats are the WORLD's, exactly
  # as the mechanics are -- written by a seed file or by `Quest::Generator` at
  # `rake game:new`, exported and seeded with the world, and touched by no
  # player ever. Which beats somebody has REACHED is `Playthrough::Beat`, one
  # layer down. See `Quest`.
  has_many :quests, dependent: :destroy

  validates :title, presence: true
  validates :genre, presence: true
  validates :preface, presence: true
  validates :summary, presence: true
  validates :start_time, presence: true

  # WHAT THE PLAYER STARTS OUT HOLDING, and it is world data rather than
  # anybody's progress: the seed file's `characters[].items` under the
  # protagonist, held by the protagonist row, in the WORLD layer.
  #
  # It is the inventory's counterpart of `#opening_location` -- the one thing
  # every playthrough of this world begins from. A Location can hold two
  # parties at once, so position is handed over by reference; an `Item` is in
  # one place in one layer, so `Item::Snapshot#of_the_party!` gives each
  # playthrough ITS OWN COPY of each of these and the rows below are never
  # carried, never takeable and never in any closed set the loop reads.
  #
  # `.templates` is the whole of what makes that true: without it this would
  # also answer with every playthrough's copy the moment one of the world's own
  # people picked something up in one game.
  #
  # Only `WorldSeed::Loader` ever writes one: `rake game:new` gives a generated
  # protagonist nothing, and `Item::Registry` furnishes rooms and never people.
  # So a generated world's starting inventory is legitimately empty.
  def starting_inventory
    return Item.none if protagonist.nil?

    Item.for_character(protagonist).templates.order(:id)
  end

  # The place the story opens in. Story::Generator creates it as a stub
  # alongside the story, so it is the story's oldest location; realizing it is
  # Location::Generator.opening's whole job.
  #
  # Reads the in-memory association before the story is saved: Story::Generator
  # returns an unsaved story with its opening room already attached, and a
  # relation query on an unsaved owner finds nothing.
  def opening_location
    return locations.first unless persisted?

    locations.order(:id).first
  end

  # THE STORY'S CLOCK: what time it is in the fiction, derived rather than
  # stored. Every Scene carries the story time it happened at, so the latest one
  # is now; a story nobody has played is at its own `start_time`.
  #
  # This is the fix for wall-clock time leaking into narration. A player who
  # closes the tab for a week used to be told, in fiction, that they had been
  # gone a week, because everything that wanted to know "how long" asked
  # `Time.current`. Nothing in the game asks the wall clock about story time any
  # more: `Scene#story_timestamp` is set from this plus how long the turn took
  # (`LocationConnection.travel_minutes` for a journey, `Scene::TURN_MINUTES`
  # otherwise), and `Location#last_protagonist_visit` is stamped with it.
  #
  # It is a `MAX` over one indexed column, which is what makes it cheap enough
  # to read on every turn. It is also the story's high-water mark rather than
  # any one playthrough's: the world moves for everybody, so the schedule the
  # world runs on belongs to the story.
  def clock
    scenes.maximum(:story_timestamp) || start_time
  end

  # Runs every world mechanic that the story's clock has passed a boundary for,
  # and fires every scheduled `WorldEvent` whose hour it has reached. Returns
  # the WorldEvents, the mechanics' first. Cheap and idempotent: safe to call on
  # every turn, and the only thing that has to happen for the world to stay
  # honest after the process has been down.
  #
  # THE SCHEDULE IS HERE AND NOT IN THE AFTER-TURN PASS, and that is the one
  # ordering decision on this method. A scheduled row is due on `#clock` -- the
  # story's high-water mark, because a bomb goes off for everybody -- and this
  # is the one place in the app where the story's clock is already caught up on
  # every turn of both play modes (`Playthrough::Turn#play` and
  # `Playthrough::Mechanics#run`). Firing beside `Playthrough::Arc` instead
  # would mean two per-turn passes over one clock in two call sites, which is
  # two places that can come to disagree about whether the world has caught up.
  #
  # BEFORE THE PLAYER'S LINE IS EVEN READ, which is the shape the mechanics
  # above already have and is right for the same reason: what the world owes is
  # settled before the exits are read, so the room the classifier resolves
  # against is the room after the tide came in.
  def catch_up_world!
    now = clock

    WorldMechanic.catch_up_story!(self) + world_events.due_by(now).map { |event| event.fire!(at: now) }
  end

  # THE ARC, or nil for a world with none -- which is every world generated
  # before `Quest::Generator` shipped and every seed file with no `quest:`
  # block. `Quest.main_arc` is the one reader of "the" main arc; this is the
  # spelling everything in the app uses, so a second query cannot come to a
  # second answer.
  def main_quest = Quest.main_arc(self)

  # THE SENTENCE THIS WORLD WAS BUILT TOWARD -- the direction report's decided
  # `Story#conclusion`, and the name survives even though the column does not.
  # It reads the main arc's DEFAULT outcome, because the captain's note of
  # 2026-09-06 made endings rows and several of them; see `Quest::Outcome` for
  # why a column beside those rows would be a second record that could
  # disagree with them.
  #
  # NIL FOR A WORLD WITH NO ARC, which is the honest nothing: a story that was
  # never given a destination has none, and `Story::Doctor` says so
  # (`story_without_a_conclusion`) rather than anything here inventing one.
  def conclusion = main_quest&.conclusion

  # `protagonist: true` writes THE PLAYER, and `Character` already refuses a
  # second one (`#single_protagonist_per_story`), so this cannot quietly give a
  # world two. `Story::FirstScreen` is the caller that means it; the doctor's
  # `:no_protagonist` remedy is the caller that says so by hand.
  def create_character(protagonist: false)
    character = Character::Generator.new(self, protagonist: protagonist).generate
    if !character.save
      raise "Failed to save character: #{character.errors.full_messages.join(", ")}"
    end

    character
  end
end
