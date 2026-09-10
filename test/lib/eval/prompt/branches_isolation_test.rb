require "test_helper"

# Pins read from the launch HEAD. The main set is intentionally stale; this
# task neither replaces it nor claims its whole request matches today's code.
class Eval::Prompt::BranchesIsolationTest < ActiveSupport::TestCase
  FILES = {
    "test/fixtures/files/prompt_corpus.yml" => "152b033ddbac333f6ac13d69195a7d110b91cdc5a7048569ef5aaeba02a3d0a1",
    "db/seeds/worlds/the-salt-assizes.yml" => "e2713ede37c82a09a373b802643038538f1c94f797241683c95f34d21ef8a54d",
    "db/seeds/worlds/the-unrecorded-hour.yml" => "798e11fce582eb88b7903eda9b7cce9a505a9045f4c463064be0608e57b267ce",
    "db/eval/prompt-2026-09-05/prompt.json" => "04e7f6bb7bd1d7f96817586977ea944b75b6043da24109cb1dfea0d71740d07e"
  }.freeze

  test "main fixtures and kept bytes are unchanged" do
    FILES.each do |path, digest|
      assert_equal digest, Digest::SHA256.file(Rails.root.join(path)).hexdigest, path
    end
  end

  test "main corpus and stored prompt identities have not moved" do
    kept = Eval::Prompt::Result.load(Eval.kept_root.join("prompt-2026-09-05"))
    assert_equal "dfd1756a8f1f91b8", Eval::Prompt.digest
    assert_equal "dfd1756a8f1f91b8", kept.corpus_digest
    assert_equal "0ffc0228b538ac73", kept.prompt_digest
  end
end
