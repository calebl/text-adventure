require "test_helper"

# THE RE-SEED DECISION, asserted without a checkout, a network or a database.
#
# `bin/update` itself is not run here for the reason `Update::BinUpdateTest`'s
# header gives -- it shells to git and to `bin/rails` -- so the decision it makes
# was extracted into a pure function and this is that function. The WORDING the
# captain reads is asserted against the script's source instead.
class Update::SeedFilesTest < ActiveSupport::TestCase
  test "a world file that moved in the range means a re-seed, named" do
    decision = Update::SeedFiles.decide(changed: [ "db/seeds/worlds/the-salt-assizes.yml" ])

    assert_predicate decision, :reseed?
    assert_equal [ "db/seeds/worlds/the-salt-assizes.yml" ], decision.files
    assert_match(/1 world file moved/, decision.reason)
  end

  test "an empty range is quiet -- a pull that touched no world file re-seeds nothing" do
    decision = Update::SeedFiles.decide(changed: [])

    assert_not decision.reseed?
    assert_empty decision.files
    assert_match(/no world file moved/, decision.reason)
  end

  test "git's blank lines are not files" do
    decision = Update::SeedFiles.decide(changed: Update::SeedFiles.changed_paths("\n  \n"))

    assert_not decision.reseed?
  end

  test "no range claims nothing, and says how to ask" do
    decision = Update::SeedFiles.decide(range: false)

    assert_not decision.reseed?
    assert_match(/--seed/, decision.reason)
  end

  test "--seed forces a re-seed even with no range at all" do
    decision = Update::SeedFiles.decide(range: false, forced: true)

    assert_predicate decision, :reseed?
    assert_empty decision.files, "a forced re-seed has no range to name files from"
    assert_match(/every checked-in world file/, decision.dry_line)
  end

  test "the dry line names the files rather than rehearsing a load" do
    decision = Update::SeedFiles.decide(changed: [ "db/seeds/worlds/the-lunar-cartographer.yml" ])

    assert_equal "would reseed: db/seeds/worlds/the-lunar-cartographer.yml", decision.dry_line
  end

  test "the directory it asks git about is where the worlds actually are" do
    assert_predicate Rails.root.join(Update::SeedFiles::DIRECTORY), :directory?
    assert_equal WorldSeed::DIRECTORY.to_s, Rails.root.join(Update::SeedFiles::DIRECTORY).to_s
  end

  # WHAT THE CAPTAIN READS, asserted against the script rather than run. A dry
  # run must promise nothing it does not do, and the SUMMARY must say out loud
  # that a re-seed re-asserts the file's values -- stats included.
  class Wording < ActiveSupport::TestCase
    def source = @source ||= Rails.root.join("bin/update").read

    test "--seed is a documented flag and not just a parsed one" do
      assert_match(/ARGV\.delete\("--seed"\)/, source)
      assert_match(/--seed\s+re-assert the checked-in world files/, source)
      assert_match(/Usage: bin\/update \[--dry-run\] \[--skip-pull\] \[--seed\]/, source)
    end

    # The dry line is printed and the loader is not run: the only thing that
    # loads a world here is `game:reseed`, and it sits in the else.
    test "the dry run says what it would do and runs nothing" do
      section = source[/section "THE CHECKED-IN WORLDS".*?section "SUMMARY"/m]

      assert_match(/if DRY_RUN\s*\n\s*#.*\n\s*#.*\n\s*say seed_decision\.dry_line\s*\n\s*else/, section)
      assert_equal 1, section.scan(/loud\("bin\/rails", "game:reseed"\)/).size,
                   "the re-seed is run in more than one place"
    end

    test "it says out loud that a re-seed re-asserts the file over the world's own rows" do
      assert_match(/re-asserts the file's values over the world's own rows -- seeded stats included/, source)
      assert_match(/seeded stats included/, source[/section "SUMMARY".*/m])
    end

    test "the re-seed runs after the migrations and the steps" do
      assert_operator source.index("section \"MIGRATIONS\""), :<, source.index("section \"THE CHECKED-IN WORLDS\"")
      assert_operator source.index("APPLYING WHAT THE NEW CODE NEEDS"), :<, source.index("section \"THE CHECKED-IN WORLDS\"")
    end

    test "--help lists --seed" do
      output = %x(#{Rails.root.join("bin/update")} --help)

      assert_predicate $?, :success?
      assert_match(/--seed/, output)
    end
  end
end
