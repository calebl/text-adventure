require "test_helper"

# THE SCHEMA'S DECLARED VERSION IS THE LATEST MIGRATION'S, and this is the
# suite asking.
#
# WHY IT EXISTS: on 2026-09-08 two PRs merged the same morning, each adding a
# migration whose version had been written by hand as the same round timestamp,
# `20260908120000`. Each PR was green alone -- the collision does not exist on
# either branch, it comes into being at the merge -- and `bin/update` on a fresh
# pull then raised `ActiveRecord::DuplicateMigrationVersionError` and ran no
# migration at all. The cure is `bin/rails generate migration`, whose version is
# the exact UTC second; `AGENTS.md` carries that as a rule.
#
# WHAT THIS TEST IS *NOT*: the duplicate-version check. That check cannot live
# in the suite, and it was tried here first. `ActiveRecord::Migrator#validate`
# raises on a duplicate while the test environment is still booting its schema,
# so a collision kills `bin/rails test` at load with that same error before a
# single test runs -- Rails already says it, louder and earlier than an
# assertion could. A test asserting what the boot has already refused to reach
# is a test that can never fail.
#
# WHAT IS LEFT IS THE ONE DIRECTION RAILS DOES NOT CHECK. A dump declaring a
# version *behind* a migration file is caught too -- the pending-migrations
# guard aborts the suite naming the file. A dump declaring a version *ahead* of
# every file is caught by nothing: no migration is pending, so Rails is content,
# and `db:schema:load` on a fresh checkout stamps a high-water mark for a
# migration that does not exist -- after which the real one never runs. That is
# a hand-edit typo away from any fix for a collision, today's included, because
# breaking a collision means renaming a file and retyping this number. It is the
# failure this pins, and it is proved to fail rather than hoped to.
#
# IT READS THE DIRECTORY AND THE DUMP -- no connection, no load of a migration
# class -- so it costs two file reads and runs everywhere.
class MigrationVersionsTest < ActiveSupport::TestCase
  MIGRATE_DIRECTORY = Rails.root.join("db/migrate")
  SCHEMA = Rails.root.join("db/schema.rb")

  test "db/schema.rb declares the latest migration's version" do
    latest = Dir.children(MIGRATE_DIRECTORY).grep(/\.rb\z/).map { |name| name[/\A\d+/] }.compact.max
    declared = SCHEMA.read[/define\(version: ([\d_]+)\)/, 1]&.delete("_")

    assert_equal latest, declared, <<~FAILED
      db/schema.rb declares version #{declared.inspect}, but the latest file in
      db/migrate is #{latest.inspect}. A dump that disagrees with the directory
      stamps the wrong high-water mark into every database loaded from it, and
      nothing else in Rails will tell you.

      Run `bin/rails db:migrate` on an up-to-date database to redump, or edit
      `define(version:)` to #{latest} if you renamed a migration by hand.
    FAILED
  end
end
