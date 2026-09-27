require "test_helper"

# WHAT IS VENDORED FROM THE ENGINE IS ITS OWN, BYTE FOR BYTE. `bin/rails
# engine:vendored` checks this checkout against the pinned engine commit's
# source; here it is checked against a stand-in source built from this
# checkout, so every way a copy can part from the engine's is named.
class EngineVendoredTest < ActiveSupport::TestCase
  test "a source that holds exactly what is vendored here has no problem" do
    with_source { |source| assert_empty EngineSweep::Vendored.problems(source) }
  end

  test "a golden that differs by one byte is named" do
    with_source do |source|
      golden = source.join("parity/goldens/a-thing-can-be-thrown.json")
      golden.write(golden.read.sub('"hp": ', '"hp":  '))

      assert_equal [ "golden a-thing-can-be-thrown.json differs from the engine's goldens/a-thing-can-be-thrown.json" ],
                   EngineSweep::Vendored.problems(source)
    end
  end

  test "a golden on one side only is named, whichever side" do
    with_source do |source|
      source.join("parity/goldens/a-thing-can-be-thrown.json").delete
      source.join("parity/goldens/a-script-nobody-wrote.json").write("{}\n")

      assert_equal [ "golden a-script-nobody-wrote.json is in the engine's goldens and not here",
                     "golden a-thing-can-be-thrown.json is not in the engine's goldens" ],
                   EngineSweep::Vendored.problems(source)
    end
  end

  test "a script the engine stores differently is named" do
    with_source do |source|
      script = source.join("parity/scripts/a-thing-can-be-thrown.yml")
      script.write("#{script.read}# a comment\n")

      assert_equal [ "script a-thing-can-be-thrown.yml differs from the engine's parity/scripts/a-thing-can-be-thrown.yml" ],
                   EngineSweep::Vendored.problems(source)
    end
  end

  test "an engine-owned portion that differs, and a list of them that differs, are named" do
    with_source do |source|
      portion = source.join("vectors/#{EngineVectors::ENGINE_OWNED.first}.json")
      portion.write(portion.read.sub("[", "[ "))
      source.join("vectors/ENGINE_OWNED").write("#{EngineVectors::ENGINE_OWNED.join("\n")}\nroll\n")

      problems = EngineSweep::Vendored.problems(source)

      assert_equal 2, problems.size, problems.inspect
      assert_match(/the engine owns .*"roll"/, problems.first)
      assert_equal "vector portion #{portion.basename} differs from the engine's vectors/#{portion.basename}", problems.last
    end
  end

  test "a source with no list of the engine's portions says what it lacks" do
    with_source do |source|
      source.join("vectors/ENGINE_OWNED").delete

      assert_equal [ "the engine source at #{source} has no vectors/ENGINE_OWNED" ], EngineSweep::Vendored.problems(source)
    end
  end

  test "the pin is read from the extension's manifest" do
    assert_match(/\A\h{40}\z/, EngineSweep::Vendored.pin)
  end

  private

  # An engine source holding exactly what this checkout vendors.
  def with_source
    Dir.mktmpdir("engine-source") do |directory|
      source = Pathname(directory)
      %w[parity/goldens parity/scripts vectors].each { |path| source.join(path).mkpath }
      Dir.glob(Rails.root.join(EngineSweep::Parity::DIRECTORY, "*.json")).reject { |path| path.end_with?(".checks.json") }
         .each { |path| FileUtils.cp(path, source.join("parity/goldens")) }
      EngineSweep.scripts.each { |script| source.join("parity/scripts/#{script.name}.yml").write(EngineSweep::Vendored.stripped(script.path)) }
      EngineVectors::ENGINE_OWNED.each { |portion| FileUtils.cp(Rails.root.join(EngineVectors::DIRECTORY, "#{portion}.json"), source.join("vectors")) }
      source.join("vectors/ENGINE_OWNED").write("# The portions this engine owns.\n#{EngineVectors::ENGINE_OWNED.join("\n")}\n")
      yield source
    end
  end
end
