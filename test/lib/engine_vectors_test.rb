require "test_helper"

# THE COMMITTED VECTORS ARE WHAT THE RUBY CODE ANSWERS TODAY. Regenerated in
# memory and compared byte for byte, so a change to any rule they cover fails
# here until `rake engine:vectors` is run and the diff is committed with it.
# The engine's own portions (`EngineVectors::ENGINE_OWNED`) are not Ruby's to
# regenerate: they are vendored from the pinned engine (`bin/rails
# engine:vendored`).
class EngineVectorsTest < ActiveSupport::TestCase
  DIRECTORY = Rails.root.join(EngineVectors::DIRECTORY)

  test "the committed vectors match what the engine answers now" do
    stale = EngineVectors.files.reject { |name, body| DIRECTORY.join(name).exist? && DIRECTORY.join(name).read == body }

    assert_empty stale.keys, "run `bin/rails engine:vectors` and commit the diff; see docs/engine-vectors.md"
  end

  # The model registry is not dumped, and which id a model row takes depends
  # on which earlier test filled the table, so a chat's reference into it
  # would make the vectors depend on the order tests ran in.
  test "a reference into a table the dump skips is written as null" do
    EngineVectors.rolled_back do
      model = Model.create!(model_id: "vector-probe", name: "vector-probe", provider: "openrouter")
      Chat.new(purpose: "location", ruby_llm_model_id: model.id).save!(validate: false)

      assert_equal [ nil ], EngineVectors::Records.dump.fetch("chats").map { |row| row.fetch("ruby_llm_model_id") }
    end
  end

  test "every file in the directory is a portion that is generated here or vendored from the engine" do
    expected = (EngineVectors::PORTIONS.keys | EngineVectors::ENGINE_OWNED).map { |portion| "#{portion}.json" }.sort

    assert_equal expected, DIRECTORY.children.map { |path| path.basename.to_s }.sort
  end

  # `Location::SpotTest` pins this spot by hand; the vectors carry it too.
  test "the one-cell spot the model test pins is a vector" do
    one_cell = JSON.parse(DIRECTORY.join("spot.json").read).fetch("cases").first

    assert_equal({ "x" => 4, "y" => 9, "z" => 0, "width" => 1, "depth" => 1 }, one_cell.dig("input", "box"))
    assert_equal 1, one_cell.dig("input", "seed")
    assert_equal [ [ 4, 9 ] ], one_cell["output"]
  end

  # `Playthrough::GrammarTest` pins this throw by hand; the vectors carry it too.
  test "the throw the grammar test pins is a vector" do
    throw = JSON.parse(DIRECTORY.join("grammar.json").read).fetch("cases")
                .find { |one| one["input"] == { "world" => "office", "typed" => "/throw the daybook at Halkett Rowe" } }

    assert_equal "throw -> Ward Office 12 daybook at Halkett Rowe", throw.dig("output", "reading_first", "understood")
    assert_equal "grammar", throw.dig("output", "reading_first", "resolved_by")
  end

  test "every line of the labelled classifier corpus is a vector" do
    ids = JSON.parse(DIRECTORY.join("grammar_corpus.json").read).fetch("cases").map { |one| one.dig("input", "id") }

    assert_equal Eval::Classifier.corpus.lines.map(&:id), ids
  end

  # The two System One requests the game keeps as fixtures are cases of the
  # portions the engine owns, so the engine is held to them.
  test "the two stored System One requests are vectors" do
    scored = JSON.parse(DIRECTORY.join("classifier_request.json").read).fetch("cases")
                 .find { |one| one["input"] == { "world" => "scored", "typed" => "ask Rowe and Perrin what happened at four o'clock" } }
    stored = JSON.parse(file_fixture("scored_classifier_request.json").read)

    assert_equal stored.fetch("state"), scored.dig("output", "state")
    assert_equal JSON.parse(file_fixture("volition_system_one_request.json").read),
                 JSON.parse(DIRECTORY.join("volition_request.json").read).fetch("cases").first.fetch("output")
  end

  test "the classifier and prompt sets' digests are the ones their digest tasks print" do
    cases = JSON.parse(DIRECTORY.join("request_identity.json").read).fetch("cases").index_by { |one| one["name"] }

    assert_equal Eval::Classifier::Version.offline, cases.fetch("classifier set").dig("output", "identity")
    assert_equal Eval::Prompt::RequestVersion.offline.fetch(:request_identity), cases.fetch("prompt set").dig("output", "identity")
  end

  test "each file declares the format and version it is written in" do
    (EngineVectors::PORTIONS.keys | EngineVectors::ENGINE_OWNED).each do |portion|
      document = JSON.parse(DIRECTORY.join("#{portion}.json").read)

      assert_equal [ EngineVectors::FORMAT, EngineVectors::FORMAT_VERSION, portion ],
                   document.values_at("format", "version", "portion")
    end
  end
end
