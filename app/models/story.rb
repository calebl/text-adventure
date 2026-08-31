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

  validates :title, presence: true
  validates :genre, presence: true
  validates :preface, presence: true
  validates :summary, presence: true
  validates :start_time, presence: true

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
  # and returns the WorldEvents. Cheap and idempotent: safe to call on every
  # turn, and the only thing that has to happen for the world to stay honest
  # after the process has been down.
  def catch_up_world!
    WorldMechanic.catch_up_story!(self)
  end

  def create_character
    character = Character::Generator.new(self).generate
    if !character.save
      raise "Failed to save character: #{character.errors.full_messages.join(", ")}"
    end

    character
  end
end
