class Scene < ApplicationRecord
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
  # the turn log (PlaythroughsController#scene_log) was never affected and is
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

  validates :description, presence: true
  validates :story_timestamp, presence: true
  validate :single_opening_scene_per_story

  after_create :mark_location_visit

  scope :openings, -> { where(is_opening: true) }

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
