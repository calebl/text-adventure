require "test_helper"

# THE STALE-EXTENSION DECISION, asserted without a toolchain: `decide` over a
# stamp's text, and `check` over a scratch crate on disk.
class Update::EngineStampTest < ActiveSupport::TestCase
  PIN = "52350f163158afe26cb10d26d3fdde48fa09dbd1".freeze
  EXPECTED = { "rev" => PIN, "lock" => "a" * 64, "crate" => "b" * 64 }.freeze

  def stamp(fields) = fields.map { |key, value| "#{key}: #{value}\n" }.join

  def decide(stamp_text, built: true) = Update::EngineStamp.decide(built: built, stamp: stamp_text, expected: EXPECTED)

  test "a missing stamp is stale: nothing says what the library was built from" do
    decision = decide(nil)

    assert_predicate decision, :stale?
    assert_match(/no build stamp/, decision.reason)
  end

  test "a stamp that matches the checkout is current" do
    assert_not decide(stamp(EXPECTED)).stale?
  end

  test "a stamp from another engine commit is stale, and names both" do
    decision = decide(stamp(EXPECTED.merge("rev" => "0" * 40)))

    assert_predicate decision, :stale?
    assert_match(/built from engine 0000000; the pin is 52350f1/, decision.reason)
  end

  test "a stamp from another Cargo.lock is stale" do
    decision = decide(stamp(EXPECTED.merge("lock" => "c" * 64)))

    assert_predicate decision, :stale?
    assert_match(/another Cargo\.lock/, decision.reason)
  end

  test "a stamp from other crate sources is stale" do
    assert_predicate decide(stamp(EXPECTED.merge("crate" => "c" * 64))), :stale?
  end

  test "a build against a local engine is not the pin" do
    assert_predicate decide(stamp(EXPECTED.merge("rev" => "local /somewhere/engine"))), :stale?
  end

  test "no library at all is stale whatever the stamp says" do
    decision = decide(stamp(EXPECTED), built: false)

    assert_predicate decision, :stale?
    assert_match(/not built yet/, decision.reason)
  end

  test "on disk: engine:build's stamp is current until the pin or the lockfile moves" do
    Dir.mktmpdir("engine-stamp") do |crate|
      FileUtils.mkdir_p(File.join(crate, "src"))
      FileUtils.mkdir_p(File.join(crate, "build"))
      File.write(File.join(crate, "Cargo.toml"),
                 %(renderedstep-engine = { git = "https://github.com/renderedstep/engine", rev = "#{PIN}" }\n))
      File.write(File.join(crate, "Cargo.lock"), "version = 4\n")
      File.write(File.join(crate, "src/lib.rs"), "// crate\n")
      File.write(File.join(crate, "build/renderedstep_native.so"), "")

      assert Update::EngineStamp.outdated?(crate), "a library without a stamp is outdated"
      assert_predicate Update::EngineStamp.check(crate), :stale?

      Update::EngineStamp.write!(crate)
      assert_not Update::EngineStamp.check(crate).stale?
      assert_not Update::EngineStamp.outdated?(crate)

      File.write(File.join(crate, "Cargo.lock"), "version = 4\n# moved\n")
      assert_predicate Update::EngineStamp.check(crate), :stale?
      assert Update::EngineStamp.outdated?(crate)

      Update::EngineStamp.write!(crate)
      File.write(File.join(crate, "Cargo.toml"), File.read(File.join(crate, "Cargo.toml")).sub(PIN, "1" * 40))
      assert_match(/the pin is 1111111/, Update::EngineStamp.check(crate).reason)

      FileUtils.rm(File.join(crate, "build/renderedstep_native.so"))
      assert_not Update::EngineStamp.outdated?(crate), "an unbuilt extension is not an old one"
    end
  end

  test "the checked-in crate pins a commit the stamp can read" do
    assert_match(/\A\h{40}\z/, Update::EngineStamp.expected["rev"])
  end

  test "the stamp sits where git ignores it" do
    _, status = Open3.capture2e("git", "check-ignore", "-q", File.join(Update::EngineStamp::CRATE, Update::EngineStamp::FILE))

    assert_predicate status, :success?
  end
end
