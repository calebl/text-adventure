require "test_helper"

# HOW POPULATED A PLACE IS: the word a model picks and the number the engine
# rolls inside it. The captain's ruling of 2026-09-07 is quoted in the file's
# header; what is pinned here is the split -- the model never writes a count,
# the engine never overrules a word, and both rolls are re-derivable for ever --
# the word from the room's NAME and the count from the room's own generator,
# which is the property `rake game:sweep` and `DRY_RUN=1` are worth anything
# because of.
class Location::PopulationTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
  end

  # THE ROOM'S OWN GENERATOR, seeded on its NAME -- the same one `.count_for`
  # opens. `Location::Danger.generator_for` is NOT it any more and must not be
  # used here: that one keys on the row and is what the cast rolls come out of.
  def rng(room) = Location::Population.generator_for(room)

  # ------------------------------------------------------------------------
  # THE TABLE.

  test "every band draws only counts the room cap can hold" do
    Location::Population::BANDS.each do |label, band|
      assert_operator band.max, :<=, Character::Registry::MAX_PER_ROOM,
                      "#{label} can draw more people than a room may hold"
      assert_operator band.min, :>=, 0, "#{label} can draw a negative number of people"
      assert_predicate band, :any?, "#{label} has nothing to draw"
    end
  end

  # THE SCHEMA'S BOUND AND THE WIDEST BAND ARE ONE NUMBER, read off the table
  # rather than written beside it -- `Location::DetailSchema` asks for `MOST`,
  # so a band widened here widens the schema in the same commit and cannot
  # quietly ask for a person the answer has no room for.
  test "MOST is the top of the widest band" do
    assert_equal Location::Population::BANDS.values.flatten.max, Location::Population::MOST
  end

  test "the labels are what a row may carry" do
    assert_equal Location::Population::BANDS.keys, Location::Population::LABELS

    Location::Population::LABELS.each do |label|
      assert_predicate build(:location, story: @story, population: label), :valid?
    end
  end

  # A WORD OUTSIDE THE TABLE CANNOT BE WRITTEN, which is `locations.danger`'s
  # rule: the labels are the whole of what a population is, and a fourth arrived
  # from somewhere that is not the engine.
  test "a word the table has no band for is refused by the row" do
    assert_not_predicate build(:location, story: @story, population: "heaving"), :valid?
  end

  # AND NIL IS A STATE RATHER THAN A MISSING VALUE. Four kinds of room are
  # honestly in it -- see the file's header -- so it has to be writable.
  test "no word at all is a valid row" do
    assert_predicate build(:location, story: @story, population: nil), :valid?
  end

  # ------------------------------------------------------------------------
  # THE WORD.

  test "a row that carries a word is answered with it" do
    room = create(:location, story: @story, population: "a crowd")

    assert_equal "a crowd", Location::Population.label_for(room, rng: rng(room))
  end

  test "a row with no word rolls one the engine can produce" do
    room = create(:location, :population_unset, story: @story)

    assert_includes Location::Population::ROLLED, Location::Population.label_for(room, rng: rng(room))
  end

  # THE WORD IS THE ROOM'S AND NOT THE ROW'S, which is what makes it survive a
  # world being exported and loaded again: every id changes and the words do not.
  # It is also what keeps the realization bench's staged worlds stable, since
  # `Eval::Realization::Stage` re-loads a world per repetition.
  test "the same room in a re-seeded world keeps its word" do
    room = create(:location, :population_unset, story: @story, name: "The Tide Post")
    elsewhere = create(:location, :population_unset, story: create(:story), name: "the Tide Post")

    assert_equal Location::Population.count_for(room), Location::Population.count_for(elsewhere)
    assert_equal Location::Population.label_for(room, rng: rng(room)),
                 Location::Population.label_for(elsewhere, rng: rng(elsewhere))
  end

  # AND IT IS NOT `String#hash`, which `Roll`'s header refuses by name: that is
  # salted per process, so the same room would come out differently after a
  # restart. This pins the checksum against a value computed outside the app.
  test "the name is turned into an integer the same way in any process" do
    room = create(:location, story: @story, name: "The Tide Post")

    assert_equal Zlib.crc32("tide post"), Location::Population.key_for(room)
  end

  test "the fallback can only roll words the table has a band for" do
    assert_equal [], Location::Population::ROLLED - Location::Population::LABELS
  end

  # THE OPENING ROOM IS NOT SPECIAL-CASED, and the captain's ruling of
  # 2026-09-05 is why it does not need to be: *"the opening room should not
  # guarantee at least one person. The protagonist can start by themselves."*
  # It is a row nothing ever named as an exit, so it takes the same fallback
  # every unnamed room takes -- and `nobody` is in that table, which is the
  # whole of the guarantee not being made.
  test "nobody is one of the words a room nobody picked for can roll" do
    assert_includes Location::Population::ROLLED, "nobody"
  end

  # A WORD PER ROOM AND NOT A WORD PER RUN. Thirty-two rooms and not four, for
  # `Location::DangerTest`'s reason one file over: `ROLLED` is weighted, so a
  # handful of rooms coming out the same way is not evidence that anything is
  # being rolled.
  test "different rooms with no word roll different words" do
    rooms = 32.times.map { |n| create(:location, :population_unset, story: @story, name: "Room #{n}") }
    words = rooms.map { |room| Location::Population.label_for(room, rng: rng(room)) }

    assert_operator words.uniq.size, :>, 1,
                    "every room in a world came out the same way, so nothing is being rolled"
    assert_equal [], words.uniq - Location::Population::ROLLED
  end

  test "one room's word is the same word in any process" do
    room = create(:location, :population_unset, story: @story)

    assert_equal Location::Population.label_for(room, rng: rng(room)),
                 Location::Population.label_for(room, rng: rng(room))
  end

  # ------------------------------------------------------------------------
  # THE COUNT.

  test "a count is drawn from inside the word's own band" do
    Location::Population::BANDS.each do |label, band|
      drawn = 40.times.map { |n| Location::Population.draw(label, rng: Random.new(n)) }

      assert_equal [], drawn.uniq - band, "#{label} drew a count outside its band"
    end
  end

  test "nobody is nobody, every time" do
    assert_equal [ 0 ], 40.times.map { |n| Location::Population.draw("nobody", rng: Random.new(n)) }.uniq
  end

  # A CROWD IS NEVER EMPTY AND A PERSON OR TWO IS NEVER NOBODY. The words mean
  # something or the pick means nothing.
  test "every word but nobody draws at least one person" do
    (Location::Population::LABELS - [ "nobody" ]).each do |label|
      drawn = 60.times.map { |n| Location::Population.draw(label, rng: Random.new(n)) }

      assert_operator drawn.min, :>=, 1, "#{label} drew a room with nobody in it"
    end
  end

  # THE WEIGHTING INSIDE A BAND IS THE LIST, `Location::Danger::ROLLED`'s shape:
  # a count written twice is twice as likely. Sixty draws and a band, not a
  # share, because this asserts that the weighting is USED -- both faces come
  # up -- rather than pinning a measured frequency a run could miss.
  test "a band with a repeated count leans on it" do
    drawn = 120.times.map { |n| Location::Population.draw("a person or two", rng: Random.new(n)) }
    counts = drawn.tally

    assert_operator counts.fetch(1, 0), :>, counts.fetch(2, 0),
                    "the middle word does not lean towards one person"
  end

  test "one room's count is the same count in any process" do
    room = create(:location, :population_unset, story: @story)
    twice = 2.times.map { Location::Population.count_for(room) }

    assert_equal twice.first, twice.last
  end
end
