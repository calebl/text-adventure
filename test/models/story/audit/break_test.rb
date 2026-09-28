require "test_helper"

# `break_untold`: the records say a turn broke a thing and the fact the writer
# was handed does not say so. Two records against each other and no prose, so
# there is no corpus to measure it on and none is needed.
#
# THE RECEIPTS BELOW ARE THE RUST ENGINE'S OWN WORDS for a drop and a throw
# that broke something, copied here because the writer is in that engine and
# not in this repository. Each says BROKE in capitals, which is what
# `Story::Audit::Receipt#broke?` reads.
class Story::Audit::BreakTest < ActiveSupport::TestCase
  DROPPED = "ON THIS TURN, and not before it, Ada Hollin put the clay jar down, and it BROKE on the floor of " \
            "The Workshop. Until this turn it WAS in their hands. It is not lying anywhere now: it is broken and " \
            "gone, and nobody can pick it up, carry it or use it again.".freeze

  THROWN = "Ada Hollin threw the clay jar through the way out into The Kiln Yard, and it BROKE where it landed. " \
           "The clay jar is NO LONGER CARRIED and is not lying anywhere, in this room or in The Kiln Yard: it is " \
           "broken and gone, and nobody can pick it up, carry it or use it again.".freeze

  # The fact a drop that did not break is told with, which says nothing about a break.
  LYING = "ON THIS TURN, and not before it, Ada Hollin put the clay jar down. Until this turn it WAS in their " \
          "hands: it is no longer carried, and it is now lying in The Workshop, where it stays until somebody " \
          "picks it up.".freeze

  setup do
    @story = create(:story)
    @room = create(:location, story: @story)
    @player = create(:character, :protagonist, story: @story)
    template = create(:item, character: nil, location: @room, name: "clay jar", fragility: "brittle")
    @game = create(:playthrough, story: @story, character: @player, current_location: @room)
    @jar = @game.items.find_by!(template: template)
  end

  def scene_for(action, engine_fact, at: @story.start_time)
    create(:scene, story: @story, location: @room, description: "The jar hits the flagstones.",
                   engine_fact: engine_fact, resolved_action: action, acted_on: @jar, story_timestamp: at)
  end

  def break_jar! = @jar.update!(disposition: "broken", location: nil, character: nil, x: nil, y: nil)

  def audit = Story::Audit.new(@story)

  def codes(audit) = audit.flags.map(&:code)

  test "a turn that broke a thing and told the writer so is not flagged" do
    break_jar!
    scene_for("drop", DROPPED)

    assert_not_includes codes(audit), :break_untold
    assert_equal 1, audit.judgeable_for(:break_untold)
  end

  test "a turn that broke a thing and told the writer it was lying there is flagged" do
    break_jar!
    scene = scene_for("drop", LYING)

    found = audit.flags.select { |flag| flag.code == :break_untold }
    assert_equal [ scene ], found.map(&:scene)
    assert_predicate found.first, :contradiction?
    assert_equal "clay jar", found.first.evidence[:item]
  end

  test "only the last drop or throw of a broken thing is the one that broke it" do
    scene_for("drop", LYING)
    scene_for("take", "picked up", at: @story.start_time + 60)
    last = scene_for("throw", THROWN, at: @story.start_time + 120)
    break_jar!

    assert_not_includes codes(audit), :break_untold
    assert_equal 1, audit.judgeable_for(:break_untold)
    assert_not audit.send(:broke_on?, @story.scenes.order(:id).first)
    assert audit.send(:broke_on?, last)
  end

  test "a thing that did not break has nothing to leave untold" do
    scene_for("drop", LYING)

    assert_not_includes codes(audit), :break_untold
    assert_equal 0, audit.judgeable_for(:break_untold)
  end

  test "a broken thing's turn with no receipt is unjudged, never flagged" do
    break_jar!
    scene = scene_for("drop", nil)

    assert_not_includes codes(audit), :break_untold
    assert_equal [ scene ], audit.unjudged.select { |skipped| skipped.code == :break_untold }.map(&:scene)
  end
end
