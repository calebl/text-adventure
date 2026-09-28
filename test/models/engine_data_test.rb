require "test_helper"

class EngineDataTest < ActiveSupport::TestCase
  def files_on_disk
    Dir[EngineData::ROOT.join("**/*.yml")].map do |path|
      Pathname(path).relative_path_from(EngineData::ROOT).to_s.delete_suffix(".yml")
    end.sort
  end

  test "every declared file exists in exactly one home, and every file on disk is declared" do
    assert_equal EngineData::SCHEMAS.keys.sort, (files_on_disk + EngineData::ENGINE_OWNED).sort
    assert_empty files_on_disk & EngineData::ENGINE_OWNED, "a file the engine owns has no second copy here"
  end

  # The engine's data is every engine-owned file this game declares, and
  # physics, whose tables only the engine reads.
  test "the files the engine owns are the engine's own data files" do
    assert_equal (EngineData::ENGINE_OWNED + [ "physics" ]).sort, Playthrough::Requests.data.keys.sort
  end

  test "an engine-owned file is read from the engine's data, never from the directory here" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "scene"))
      File.write(File.join(root, "scene/ending.yml"), "instructions: from a stray copy\n")
      text = "instructions: from the engine\n"

      assert_equal "from the engine", EngineData.send(:load, "scene/ending", root: root, engine: { "scene/ending" => text }).fetch("instructions")
      assert_match "has no such file", assert_raises(EngineData::Error) { EngineData.send(:load, "scene/ending", engine: {}) }.message
    end
  end

  test "every file parses and matches its schema" do
    EngineData::SCHEMAS.each_key do |name|
      data = EngineData.fetch(name)

      assert_predicate data, :frozen?, name
      assert_equal EngineData::SCHEMAS.fetch(name).keys.sort, data.keys.sort, name
    end
  end

  test "a value read twice is the same object" do
    assert_same EngineData.fetch("scene/narrator"), EngineData.fetch("scene/narrator")
  end

  test "an undeclared file is refused" do
    error = assert_raises(EngineData::Error) { EngineData.fetch("no/such/file") }
    assert_match "no schema declared", error.message
  end

  # The private loader is driven against a scratch root so the checked-in
  # files are never touched and nothing is memoized from it.
  def load_from(root, name)
    EngineData.send(:load, name, root: root)
  end

  test "a missing file, bad YAML and a wrong shape each raise" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "story"))
      path = File.join(root, "story/generator.yml")

      assert_match "is missing", assert_raises(EngineData::Error) { load_from(root, "story/generator") }.message

      File.write(path, "system_prompt: [unclosed\n")
      assert_match "not valid YAML", assert_raises(EngineData::Error) { load_from(root, "story/generator") }.message

      File.write(path, "system_prompt: 3\n")
      assert_match "expected String", assert_raises(EngineData::Error) { load_from(root, "story/generator") }.message

      File.write(path, "system_prompt: x\nextra: y\n")
      assert_match "keys", assert_raises(EngineData::Error) { load_from(root, "story/generator") }.message
    end
  end

  test "a closed table keeps the order it is written in" do
    assert_equal [ "no inside", "one room", "a few rooms", "a warren of rooms" ], Location::Parameters::INSIDE.keys
    assert_equal Location::Parameters::DANGER.keys, Location::Parameters::LADDER
    assert_equal Location::SAFE, Location::Parameters::LADDER.first
  end
end
