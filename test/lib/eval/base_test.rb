require "test_helper"
require "tmpdir"

# THE BASE WORLD A SWEEP COPIES, AND THE GUARD IN FRONT OF IT.
#
# The bug this pins is a real one and it cost a sweep: an interrupted build left
# `tmp/eval/base.sqlite3` behind at ZERO BYTES, both guards asked `File.exist?`,
# and fifteen runs were started from an empty file and died on `Could not find
# table 'stories'` -- before any model call, so it cost nothing but the wait and
# an error a long way from its cause.
#
# So the contract is stated twice, at two altitudes: `Eval::Base` answers WHY a
# file is not a base, and `script/eval_base.rb` REBUILDS one rather than
# trusting it. The second test really runs the builder, because the decision
# under test lives in the script and asserting the predicate alone would leave
# the guard free to go back to `File.exist?`.
class Eval::BaseTest < ActiveSupport::TestCase
  # A base as far as the guard can tell: the two tables a run reads and the
  # three worlds it plays. Enough to be usable, and nothing else -- what makes
  # the file a real base is the builder's business, not the guard's.
  def build_usable(path, titles: Eval::STORIES, tables: Eval::Base::REQUIRED_TABLES)
    database = SQLite3::Database.new(path.to_s)
    tables.each { |table| database.execute("CREATE TABLE #{table} (id integer primary key, title varchar)") }
    titles.each { |title| database.execute("INSERT INTO stories (title) VALUES (?)", [ title ]) } if tables.include?("stories")
    database.close
    path
  end

  def in_a_directory
    Dir.mktmpdir("eval-base-test") { |directory| yield Pathname(directory) }
  end

  test "a file that is there is not the question -- an empty one is refused" do
    in_a_directory do |directory|
      path = directory.join("base.sqlite3")
      FileUtils.touch(path)

      assert File.exist?(path), "the fixture is the bug: the file exists"
      assert_not Eval::Base.usable?(path)
      assert_equal "it is empty (0 bytes)", Eval::Base.unusable_reason(path)
    end
  end

  test "a file with no schema in it is refused" do
    in_a_directory do |directory|
      path = directory.join("base.sqlite3")
      build_usable(path, tables: [ "junk" ])

      assert_operator File.size(path), :>, 0, "the fixture is a real SQLite file, not an empty one"
      assert_equal "it has no stories or models table", Eval::Base.unusable_reason(path)
    end
  end

  test "half a schema is refused too" do
    in_a_directory do |directory|
      path = directory.join("base.sqlite3")
      build_usable(path, tables: [ "stories" ])

      assert_equal "it has no models table", Eval::Base.unusable_reason(path)
    end
  end

  test "a schema with a world missing is refused -- the builder aborts after the connection is open" do
    in_a_directory do |directory|
      path = directory.join("base.sqlite3")
      build_usable(path, titles: [ Eval::STORIES.first ])

      assert_equal "it is missing the seeded world(s) #{Eval::STORIES.drop(1).join(", ")}",
                   Eval::Base.unusable_reason(path)
    end
  end

  test "something that is not a SQLite database at all is refused" do
    in_a_directory do |directory|
      path = directory.join("base.sqlite3")
      path.write("this is not a database\n" * 64)

      assert_match(/not a readable SQLite database|could not be read/, Eval::Base.unusable_reason(path))
    end
  end

  test "a base with the tables and the worlds is used" do
    in_a_directory do |directory|
      path = build_usable(directory.join("base.sqlite3"))

      assert_nil Eval::Base.unusable_reason(path)
      assert Eval::Base.usable?(path)
    end
  end

  test "a missing file is not a base either" do
    in_a_directory { |directory| assert_equal "it does not exist", Eval::Base.unusable_reason(directory.join("nothing.sqlite3")) }
  end

  # THE CONTRACT ITSELF: the builder replaces an unusable base instead of
  # exiting 0 on it. Offline -- `db/schema.rb` and the seed files are both files
  # on disk -- and it writes only to the path it is given, which is a temporary
  # directory of this test's own.
  test "the builder rebuilds a zero-byte base rather than trusting it" do
    in_a_directory do |directory|
      path = directory.join("base.sqlite3")
      FileUtils.touch(path)

      assert build_base(path), "the builder failed"
      assert_nil Eval::Base.unusable_reason(path), "an empty base was left in place"
    end
  end

  def build_base(path)
    system({ "EVAL_BASE" => path.to_s }, Rails.root.join("bin/rails").to_s, "runner", "script/eval_base.rb",
           chdir: Rails.root.to_s, out: File::NULL, err: File::NULL)
  end
end
