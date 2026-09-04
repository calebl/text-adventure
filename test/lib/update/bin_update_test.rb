require "test_helper"

# `bin/update` AT THE SHELL. What can be asserted here cheaply, and what
# deliberately is not.
#
# WHAT IS ASSERTED: that the script parses, that it is executable, that its
# argument handling refuses what it does not understand instead of guessing,
# and -- the one that matters most -- THAT THE SOURCE CONTAINS NONE OF THE
# COMMANDS ITS HEADER PROMISES IT WILL NEVER RUN. That promise is the reason
# the captain can run this against his primary checkout at all, and it is
# exactly the kind of thing a later edit adds "just to get past" a dirty tree.
#
# WHAT IS NOT: a full `bin/update --dry-run` run. It shells out to `bin/rails`
# twice and fetches from origin, so in the suite it is either a ten-second test
# or a network-dependent one, against a `bin/rails test` that finishes in about
# a second. It is checked BY HAND instead, and the transcript goes in the PR --
# both halves of it, on a copy of a real database:
#
#   cp <a real development.sqlite3> tmp/rehearsal/pre-update.sqlite3
#   DATABASE_URL="sqlite3:tmp/rehearsal/pre-update.sqlite3" bin/update --skip-pull --dry-run
#   DATABASE_URL="sqlite3:tmp/rehearsal/pre-update.sqlite3" bin/update --skip-pull
#   DATABASE_URL="sqlite3:tmp/rehearsal/pre-update.sqlite3" bin/update --skip-pull   # must be quiet
#
# The dry pass's own promise -- that nothing is written -- is asserted per step
# in `Update::StepsTest`, which is where it can be asserted against rows.
class Update::BinUpdateTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/update")

  # EVERY GIT SUBCOMMAND IT IS ALLOWED TO RUN, and the list is short because
  # the promise is strong: eight of these nine only ask questions, and the
  # ninth is a fast-forward. Anything that could move or discard a working tree
  # -- stash, reset, checkout, switch, clean, rebase, merge, push -- is absent
  # by intent, not by oversight, so a later edit that reaches for one to "get
  # past" a dirty tree fails here.
  ALLOWED_GIT = %w[rev-parse symbolic-ref status fetch merge-base log diff pull].freeze

  def source = @source ||= SCRIPT.read

  # The git it actually RUNS, rather than the git it mentions. Every call goes
  # through `git(...)` or `loud("git", ...)`, so the subcommand is the first
  # string argument -- and a sentence in an error message telling the captain to
  # `git switch main` himself is not this script running anything.
  def git_subcommands
    source.scan(/\bgit\(\s*"([a-z-]+)"/).flatten + source.scan(/loud\(\s*"git",\s*"([a-z-]+)"/).flatten
  end

  test "it is an executable ruby script that parses" do
    assert File.executable?(SCRIPT), "bin/update is not executable"
    assert_match(/\A#!\/usr\/bin\/env ruby/, source)
    assert system("ruby", "-c", SCRIPT.to_s, out: File::NULL), "bin/update is not valid ruby"
  end

  # THE PROMISE IN ITS HEADER, ASSERTED AGAINST ITS BODY. The captain's own
  # checkout is what this runs against, so a word of git that can move a
  # working tree does not belong in it, in any branch, however convenient.
  test "it never stashes, resets, checks out, cleans, pushes or rebases anything" do
    assert_predicate git_subcommands, :any?, "no git call was found at all -- has the shape of the script changed?"
    assert_empty git_subcommands.uniq - ALLOWED_GIT,
                 "bin/update runs a git subcommand its header promises it never will"
  end

  test "it never kills a process it did not start, which is all of them" do
    code = source.lines.reject { |line| line.strip.start_with?("#") }.join

    [ /\bpkill\b/, /\bkillall\b/, /Process\.kill/, /\bkill\b\s+-/ ].each do |pattern|
      assert_no_match pattern, code, "bin/update reaches for a process it does not own"
    end
  end

  test "the only thing it does to a working tree is a fast-forward pull" do
    pulls = source.scan(/loud\(\s*"git",\s*"pull"[^\n]*/)

    assert_predicate pulls, :any?, "bin/update does not pull at all"
    pulls.each { |pull| assert_match(/--ff-only/, pull, "a pull without --ff-only can merge") }
  end

  test "--help says what the flags are and touches nothing" do
    before = %x(git rev-parse HEAD).strip
    output = %x(#{SCRIPT} --help)

    assert_predicate $?, :success?
    assert_match(/--dry-run/, output)
    assert_match(/--skip-pull/, output)
    assert_match(/never stashes, resets or checks out anything/, output)
    assert_equal before, %x(git rev-parse HEAD).strip
  end

  test "a flag it does not understand is refused rather than guessed at" do
    output = %x(#{SCRIPT} --frobnicate 2>&1)

    assert_not $?.success?, "bin/update carried on past an argument it does not know"
    assert_match(/I do not know what --frobnicate means/, output)
    assert_match(/Usage: bin\/update/, output)
  end
end
