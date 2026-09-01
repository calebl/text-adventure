# One browser session's progress through a story: which character the player is
# and where they are standing right now. The story itself stays on Story --
# this is the "someone playing it" half, so a single generated world can be
# played more than once.
class Playthrough < ApplicationRecord
  belongs_to :story
  belongs_to :character, optional: true
  belongs_to :current_location, class_name: "Location", optional: true
  belongs_to :current_scene, class_name: "Scene", optional: true

  # Generated at initialize rather than on create so the presence validation
  # below sees it. This is the only thing binding a browser session to a
  # playthrough, so it has to be unguessable.
  has_secure_token :token, length: 32, on: :initialize

  validates :token, presence: true, uniqueness: true
  validate :character_belongs_to_story
  validate :current_location_belongs_to_story
  validate :current_scene_belongs_to_story

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

  private

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
