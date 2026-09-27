require "test_helper"

# THE COMMITTED VECTORS ARE WHAT THE RUBY CODE ANSWERS TODAY. Regenerated in
# memory and compared byte for byte, so a change to any rule they cover fails
# here until `rake engine:vectors` is run and the diff is committed with it.
class EngineVectorsTest < ActiveSupport::TestCase
  DIRECTORY = Rails.root.join(EngineVectors::DIRECTORY)

  test "the committed vectors match what the engine answers now" do
    stale = EngineVectors.files.reject { |name, body| DIRECTORY.join(name).exist? && DIRECTORY.join(name).read == body }

    assert_empty stale.keys, "run `bin/rails engine:vectors` and commit the diff; see docs/engine-vectors.md"
  end

  test "every file in the directory is a portion that is generated" do
    expected = EngineVectors::PORTIONS.keys.map { |portion| "#{portion}.json" }.sort

    assert_equal expected, DIRECTORY.children.map { |path| path.basename.to_s }.sort
  end

  # `Location::SpotTest` pins this spot by hand; the vectors carry it too.
  test "the one-cell spot the model test pins is a vector" do
    one_cell = JSON.parse(DIRECTORY.join("spot.json").read).fetch("cases").first

    assert_equal({ "x" => 4, "y" => 9, "z" => 0, "width" => 1, "depth" => 1 }, one_cell.dig("input", "box"))
    assert_equal 1, one_cell.dig("input", "seed")
    assert_equal [ [ 4, 9 ] ], one_cell["output"]
  end

  test "each file declares the format and version it is written in" do
    EngineVectors::PORTIONS.each_key do |portion|
      document = JSON.parse(DIRECTORY.join("#{portion}.json").read)

      assert_equal [ EngineVectors::FORMAT, EngineVectors::FORMAT_VERSION, portion ],
                   document.values_at("format", "version", "portion")
    end
  end
end
