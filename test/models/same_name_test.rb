require "test_helper"

# The one rule every name lookup asks, pinned to the cases where the obvious
# alternatives disagree with it: SQLite's `LOWER()` (ASCII only) and
# `String#casecmp?` (full case folding). The engine folds exactly this way.
class SameNameTest < ActiveSupport::TestCase
  test "a name outside ASCII is the same name in either case" do
    assert SameName.same?("Écu of the ward", "écu of the ward")
    assert SameName.same?("ÖDÖN", "ödön")
    assert SameName.same?("ΟΔΟΣ", "οδοσ"), "downcase never writes a final sigma"
  end

  test "a sharp s is not two s's, because downcase does not fold" do
    refute SameName.same?("Straße", "STRASSE")
  end

  test "nothing wider than case: articles and spacing still count" do
    refute SameName.same?("The Supply Closet", "Supply Closet")
    refute SameName.same?("ward  stamp", "ward stamp")
  end

  test "a scope answers by any of the columns asked, first by id" do
    story = create(:story)
    first = create(:character, story: story, fullname: "Ödön Vaile", nickname: "Åke")
    create(:character, story: story, fullname: "Åke Halloran")

    assert_equal first, SameName.first(story.characters, "åke", :fullname, :nickname)
    assert SameName.any?(story.characters, "ÖDÖN VAILE", :fullname)
    refute SameName.any?(story.characters, "åke", :fullname)
    assert_nil SameName.first(story.characters, "nobody", :fullname, :nickname)
  end
end
