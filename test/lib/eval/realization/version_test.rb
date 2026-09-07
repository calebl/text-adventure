require "test_helper"

# WHICH PROMPT BUILT A SET, and specifically the SCRUB -- the one part of this
# module that decides what counts as a version of a prompt and what counts as
# the engine's own dice. Both scrubbed lines are rolls
# (`Character::Registry#slots` for who a person is, `Location::Population` for
# how many there are), both are keyed on things a staged copy of a world
# re-issues on every load, and a digest over either would call every repetition
# a different prompt version.
class Eval::Realization::VersionTest < ActiveSupport::TestCase
  def scrub(prompt) = Eval::Realization::Version.scrub(prompt)

  # THE CAST LINES, as `Location::Generator#slot_details` writes them.
  test "two runs that rolled different people are one prompt version" do
    first = "Write these people and do not change them:\n  the 1st is Shorefolk, about 44, woman"
    second = "Write these people and do not change them:\n  the 1st is Bell-Keepers, about 71, trans man"

    assert_equal scrub(first), scrub(second)
  end

  # AND THE COUNT, by POSITION rather than by wording: the line under the
  # heading, whichever of the two sentences `#people_instructions` put there.
  test "two runs that rolled different counts are one prompt version" do
    two = "## Who Is Here\nWrite EXACTLY 2 people who are in this place right now.\n- Anyone you write"
    one = "## Who Is Here\nWrite EXACTLY 1 person who is in this place right now.\n- Anyone you write"

    assert_equal scrub(two), scrub(one)
  end

  # THE HEADING ITSELF SURVIVES, because it is what the scrub is anchored on --
  # and the bullets under the count survive with it, which is the half that makes
  # the digest still worth taking.
  test "the instructions around the count are still part of the version" do
    scrubbed = scrub("## Who Is Here\nWrite EXACTLY 2 people who are in this place right now.\n- Anyone you write")

    assert_includes scrubbed, "## Who Is Here"
    assert_includes scrubbed, "- Anyone you write"
    assert_not_includes scrubbed, "EXACTLY 2"
  end

  test "a reworded instruction is a different prompt version" do
    before = "## Who Is Here\nWrite EXACTLY 2 people who are in this place right now.\n- Anyone you write"
    after = "## Who Is Here\nWrite EXACTLY 2 people who are in this place right now.\n- Anyone you name"

    assert_not_equal scrub(before), scrub(after)
  end

  # THE OTHER TWO ALLOWANCES ARE NOT ROLLED and are supposed to be constant, so
  # they stay inside the digest. A scrub that had matched on the sentence rather
  # than on the heading would have taken the items line with it.
  test "the items and exits allowances are still part of the version" do
    %w[List Name].zip([ "AT MOST 3 portable things a player could pick up", "AT MOST 2 ways out" ]).each do |verb, rest|
      line = "#{verb} #{rest}"

      assert_equal line, scrub(line)
    end
  end

  # AND BOTH BRANCHES OF THE PEOPLE BLOCK CARRY THE HEADING, which is what makes
  # scrubbing by position possible at all. Asserted against the app's own text
  # rather than a copy of it, so a branch that lost the heading fails here.
  test "the nobody branch keeps the heading the scrub is anchored on" do
    assert_match(/\A## Who Is Here\n/, Location::Generator::NOBODY_HERE)
    assert_not_includes scrub(Location::Generator::NOBODY_HERE),
                        Location::Generator::NOBODY_HERE.lines.second.strip
  end
end
