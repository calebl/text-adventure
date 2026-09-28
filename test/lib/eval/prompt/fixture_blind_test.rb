require "test_helper"

# THE PROMPT BENCH CANNOT SEE THE NARRATOR'S FIXED-PIECES LINE, and this is the
# test that says so the day it could.
#
# The engine tells the narrator a room's fixtures on a line of their own
# ("Fixed here, and not takeable: ..."), and only in a room that has one, so a
# room with none is asked for in the words it always was. No world the prompt
# bench stages has a fixture, so no case it holds ever renders that line and
# its baseline says nothing about it. That is honest only while it stays true:
# a fixture added to one of these worlds moves every request staged in that
# room without any prompt edit, and the kept sets would silently be measuring a
# prompt they were never bought on. When this goes red, the worlds changed:
# re-baseline the prompt sets the room is staged in, and delete this test.
class Eval::Prompt::FixtureBlindTest < ActiveSupport::TestCase
  test "no world the prompt bench stages stands a fixture in any room" do
    fixtures = Eval::Prompt::STORIES.flat_map do |title|
      file = Eval::Prompt::WORLD_ROOTS.map { |root| Pathname(root).join("#{WorldSeed.slug(title)}.yml") }.find(&:exist?)
      assert file, "no world file for #{title}"

      Array(YAML.safe_load_file(file, aliases: true)["locations"]).flat_map do |location|
        Array(location["items"]).select { |item| item.key?("holds") }.map { |item| "#{title}: #{location["name"]}: #{item["name"]}" }
      end
    end

    assert_empty fixtures, "the prompt bench now stages a fixture; its kept sets never saw the narrator's fixed-pieces line"
  end
end
