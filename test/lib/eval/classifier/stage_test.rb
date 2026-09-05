require "test_helper"

# THE POSITION, AND THE THREE THINGS THAT MAKE IT SAFE TO STAGE ONE.
#
# `Eval::Classifier::Stage` loads a copy of a seeded world so a bench can be run
# against a database somebody is mid-game in, and the guarantees are
# `EngineSweep::Walk`'s. They are worth their own test because every one of them
# is invisible when it works and destructive when it does not.
class Eval::Classifier::StageTest < ActiveSupport::TestCase
  test "a staged position leaves the database exactly as it found it" do
    before = { Story.count => :stories, Playthrough.count => :playthroughs, Item.count => :items }

    Eval::Classifier::Stage.open(Eval::Classifier.corpus.positions) do |stages|
      assert_equal Eval::Classifier.corpus.positions.size, stages.size
    end

    assert_equal before, { Story.count => :stories, Playthrough.count => :playthroughs, Item.count => :items }
  end

  # THE COPY IS PER POSITION AND NOT PER WORLD, and this is the test that says
  # why: the closed-set readers are live queries, so two positions cut from one
  # seed file under one title would be two playthroughs of ONE world -- and a
  # position whose setup put the daybook on the floor would put it on the floor
  # of every other position in that world.
  test "two positions of one world do not see each other's setup" do
    corpus = Eval::Classifier.corpus.subset { |line| %w[office office-empty-handed].include?(line.position) }

    Eval::Classifier::Stage.open(corpus.positions) do |stages|
      untouched = stages.fetch("office")
      emptied = stages.fetch("office-empty-handed")

      assert_equal [ "Ward Office 12 daybook" ], untouched.carried.map(&:name)
      assert_empty emptied.carried, "its setup dropped the daybook"
      assert_equal [ "filing press", "ward stamp" ], untouched.here.map(&:name).sort,
                   "and the drop must not have landed on the other position's floor"
      assert_not_equal untouched.playthrough.story_id, emptied.playthrough.story_id,
                       "one copy of the world per position is what keeps those apart"
    end
  end

  test "a position's setup is walked offline, so staging costs nothing" do
    walked = Eval::Classifier.corpus.subset { |line| line.position == "office-carrying-three" }

    EngineSweep.without_a_model do
      Eval::Classifier::Stage.open(walked.positions) do |stages|
        standing = stages.fetch("office-carrying-three")

        assert_equal "Ward Office 12", standing.location.name, "the room is stated and the room wins"
        # SORTED, because the order is `Item::Snapshot`'s and not this class's:
        # the party's seeded kit is copied when the playthrough is created and
        # the two the walk picked up land after it. What the corpus depends on
        # is the CONTENTS -- and, for an `examine`, that the floor comes before
        # the hands, which the closed-sets test below asserts.
        assert_equal [ "Perrin's private index", "Ward Office 12 daybook", "copy-room apron" ].sort,
                     standing.carried.map(&:name).sort
      end
    end
  end

  # `cast:` IS THE ONE THING NO TYPED LINE CAN DO, and it is here so that the
  # exception is visible rather than buried in a YAML key.
  test "a position may place somebody the seed file does not, through the engine's own writer" do
    corpus = Eval::Classifier.corpus.subset { |line| line.position == "office-with-perrin" }

    Eval::Classifier::Stage.open(corpus.positions) do |stages|
      standing = stages.fetch("office-with-perrin")

      assert_equal [ "Perrin Lasco", "Halkett Rowe" ], standing.cast.map(&:fullname)
      assert_not standing.cast.first.deliberately_absent?,
                 "Character#move_to! clears the marker, which is the story no longer holding -- fine for a bench"
    end
  end

  test "the closed sets a position offers are the ones the classifier will offer a model" do
    corpus = Eval::Classifier.corpus.subset { |line| line.position == "closet" }

    Eval::Classifier::Stage.open(corpus.positions) do |stages|
      standing = stages.fetch("closet")

      assert_equal [ "Ward Office 12" ], standing.offered_for(:move).map(&:name)
      assert_equal [ "Perrin's private index", "copy-room apron" ], standing.offered_for(:take).map(&:name)
      assert_equal [ "Ward Office 12 daybook" ], standing.offered_for(:drop).map(&:name)
      assert_empty standing.offered_for(:talk)
      assert_empty standing.offered_for(:other), "`other` resolves no record and never will"
      assert_includes standing.offered, "Perrin's private index"
    end
  end

  test "a room the world does not have is a loud failure and not a guess" do
    position = Eval::Classifier::Corpus::Position.new(id: "nowhere", story: "The Unrecorded Hour",
                                                      room: "The Sealed Room")

    error = assert_raises(Eval::Classifier::Stage::Unstageable) do
      Eval::Classifier::Stage.open([ position ]) { |_stages| flunk "should not have staged" }
    end
    assert_match(/no room called "The Sealed Room"/, error.message)
  end

  test "a setup line the grammar refuses is a loud failure, because the position would be wrong" do
    position = Eval::Classifier::Corpus::Position.new(id: "impossible", story: "The Unrecorded Hour",
                                                      room: "Ward Office 12",
                                                      setup: [ "take the tide-slate" ])

    error = assert_raises(Eval::Classifier::Stage::Unstageable) do
      Eval::Classifier::Stage.open([ position ]) { |_stages| flunk "should not have staged" }
    end
    assert_match(/was refused offline/, error.message)
  end

  # AN ERROR INSIDE THE BLOCK MUST NOT COME BACK AS NIL, which it did while the
  # rollback lived in an `ensure`: a raise there replaces the exception in
  # flight, so a bench that blew up returned nothing at all and the board
  # crashed somewhere else entirely.
  test "an exception inside the block propagates rather than becoming a silent nil" do
    assert_raises(ArgumentError) do
      Eval::Classifier::Stage.open(Eval::Classifier.corpus.positions.first(1)) { raise ArgumentError, "boom" }
    end
  end
end
