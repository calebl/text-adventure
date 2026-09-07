require "test_helper"

# BINDING IS A SIDE EFFECT OF ADMISSION, and these pin it at the three seams
# that already write rows -- because the whole anti-railroad claim rests on the
# arc having no writer of its own.
class Quest::BinderTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @quest = create(:quest, :generated, story: @story)
  end

  # --- the three writers -----------------------------------------------------

  test "a stub being born binds a place the arc was waiting for" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")

    warren = Location::Generator.create_stub!(@story, name: "Blackfang Warren", teaser: "a hole in the rock")

    assert_equal warren, step.reload.target
    assert_equal @story.clock, step.bound_at
  end

  test "the character registry binds a person the arc was waiting for" do
    step = create(:quest_step, :speak_to, quest: @quest, target_name: "Prince Aurel Durn")
    room = create(:location, :realized, story: @story)

    Character::Registry.new(room).admit!([ sheet_for("Prince Aurel Durn") ])

    assert_equal "Prince Aurel Durn", step.reload.target&.fullname
    assert_equal room, step.target.location
  end

  test "the item registry binds a thing the arc was waiting for" do
    step = create(:quest_step, :hold_item, quest: @quest, target_name: "the cell key")
    room = create(:location, :realized, story: @story)

    Item::Registry.new(room).admit!([ { "name" => "the cell key", "description" => "iron, cold, bent" } ])

    assert_equal "the cell key", step.reload.target&.name
  end

  # --- what it will not do ---------------------------------------------------

  test "a name that is not the one the arc waits for binds nothing" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")

    Location::Generator.create_stub!(@story, name: "the surface", teaser: "daylight")

    assert_predicate step.reload, :unbound?
  end

  test "a leading article is not part of the name" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "the Blackfang Warren")

    warren = Location::Generator.create_stub!(@story, name: "Blackfang Warren", teaser: "a hole")

    assert_equal warren, step.reload.target
  end

  test "a row of the wrong kind never binds" do
    step = create(:quest_step, :speak_to, quest: @quest, target_name: "Blackfang Warren")

    Location::Generator.create_stub!(@story, name: "Blackfang Warren", teaser: "a hole")

    assert_predicate step.reload, :unbound?
  end

  test "another story's arc is never bound" do
    step = create(:quest_step, :reach_location, quest: @quest, target_name: "Blackfang Warren")

    Location::Generator.create_stub!(create(:story), name: "Blackfang Warren", teaser: "a hole")

    assert_predicate step.reload, :unbound?
  end

  test "a doomed arc binds nothing, because its beats are unreachable by design" do
    doomed = create(:quest, :doomed, story: create(:story), title: "The Siege That Holds")
    step = create(:quest_step, :reach_location, quest: doomed, target_name: "the breach")

    Location::Generator.create_stub!(doomed.story, name: "the breach", teaser: "rubble")

    assert_predicate step.reload, :unbound?
  end

  # A playthrough's own copy of a thing is that game's progress; binding the
  # world's arc to it would point every player's arc at one player's row.
  test "only the world's own row binds, never a playthrough's copy" do
    step = create(:quest_step, :hold_item, quest: @quest, target_name: "the cell key")
    room = create(:location, :realized, story: @story)
    game = create(:playthrough, story: @story, current_location: room)
    template = create(:item, :lying, name: "the cell key", location: room)

    step.reload
    copy = create(:item, :lying, name: "the cell key", location: room, playthrough: game, template: template)
    Quest::Binder.bind!(copy)

    assert_predicate step.reload, :unbound?

    Quest::Binder.bind!(template)

    assert_equal template, step.reload.target
  end

  test "nil binds nothing and raises nothing" do
    assert_equal [], Quest::Binder.bind!(nil)
  end

  private

  def sheet_for(fullname)
    {
      "fullname" => fullname,
      "appearance" => "thin, and long past caring about it",
      "personality" => "watchful",
      "backstory" => "taken off the road three weeks ago",
      "likes" => "quiet",
      "dislikes" => "the sound of the door",
      "fears" => "being forgotten"
    }
  end
end
