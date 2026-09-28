require "test_helper"

# THE COLUMN-ORDER RESTORE, asserted on fixture text without a checkout or a
# database -- `bin/update` is not run here for the reason `Update::BinUpdateTest`
# gives, so the decision it makes is the thing under test.
class Update::SchemaOrderTest < ActiveSupport::TestCase
  COMMITTED = <<~RUBY
    ActiveRecord::Schema[8.1].define(version: 2026_09_28_102823) do
      create_table "characters", force: :cascade do |t|
        t.integer "age"
        t.datetime "created_at", null: false
        t.string "name"
        t.index ["name"], name: "index_characters_on_name"
      end

      create_table "items", force: :cascade do |t|
        t.integer "character_id"
        t.string "name"
      end

      add_foreign_key "items", "characters"
    end
  RUBY

  # What a database built migration by migration dumps: the same lines, with
  # the columns in the order the migrations added them.
  REORDERED = <<~RUBY
    ActiveRecord::Schema[8.1].define(version: 2026_09_28_102823) do
      create_table "characters", force: :cascade do |t|
        t.string "name"
        t.datetime "created_at", null: false
        t.integer "age"
        t.index ["name"], name: "index_characters_on_name"
      end

      create_table "items", force: :cascade do |t|
        t.string "name"
        t.integer "character_id"
      end

      add_foreign_key "items", "characters"
    end
  RUBY

  def decide(dumped, clean_before: true, committed: COMMITTED)
    Update::SchemaOrder.decide(path: "db/schema.rb", clean_before:, committed:, dumped:)
  end

  test "a pure reorder is restored, and says so" do
    outcome = decide(REORDERED)

    assert_predicate outcome, :restore?
    assert_equal "restored db/schema.rb (column order only).", outcome.line
  end

  test "an identical dump needs nothing" do
    assert_not decide(COMMITTED).restore?
  end

  test "a real change is not restored" do
    {
      "a missing column" => REORDERED.sub(/^\s+t\.integer "age"\n/, ""),
      "a different default" => REORDERED.sub('t.string "name"', 't.string "name", default: "x"'),
      "a newer version" => REORDERED.sub("2026_09_28_102823", "2026_09_29_000000"),
      "a changed foreign key" => REORDERED.sub('add_foreign_key "items", "characters"', 'add_foreign_key "items", "people"'),
      "a column moved between tables" => REORDERED.sub(/^(\s+)t\.integer "character_id"\n/, "")
                                                  .sub(/^(\s+)t\.integer "age"\n/, "\\0\\1t.integer \"character_id\"\n")
    }.each do |what, dumped|
      outcome = decide(dumped)

      assert_not outcome.restore?, "#{what} was forgiven as column order"
      assert_match(/more than column order; left alone/, outcome.line, what)
    end
  end

  test "lines outside a create_table block are never reordered" do
    committed = COMMITTED.sub('add_foreign_key "items", "characters"',
                              "add_foreign_key \"items\", \"characters\"\n  add_foreign_key \"items\", \"items\"")
    swapped = COMMITTED.sub('add_foreign_key "items", "characters"',
                            "add_foreign_key \"items\", \"items\"\n  add_foreign_key \"items\", \"characters\"")

    assert_not decide(swapped, committed:).restore?
  end

  test "a file that had uncommitted changes before the run is left alone, even a pure reorder" do
    outcome = decide(REORDERED, clean_before: false)

    assert_not outcome.restore?
    assert_match(/had uncommitted changes before this run, so it was left alone \(as dumped now it differs only in column order\)/,
                 outcome.line)
  end

  test "a file not committed at HEAD is left alone" do
    assert_not decide(REORDERED, committed: nil).restore?
  end

  test "the dry run says what it would do and writes nothing" do
    assert_match(/would be restored after migrating/,
                 Update::SchemaOrder.dry_line(path: "db/schema.rb", clean_before: true, migrating: true))
    assert_match(/would be left alone/,
                 Update::SchemaOrder.dry_line(path: "db/schema.rb", clean_before: false, migrating: true))
  end

  test "git's porcelain lines are paths" do
    assert_equal %w[db/schema.rb db/cable_schema.rb],
                 Update::SchemaOrder.dirty_paths(" M db/schema.rb\n?? db/cable_schema.rb\n")
  end

  # The real files, each block's columns reversed, the way the owner's machine
  # dumps them: all three must come back.
  test "every checked-in schema file, its columns reversed, is restored" do
    Update::SchemaOrder::FILES.map { Rails.root.join(it) }.select(&:exist?).each do |file|
      committed = file.read
      dumped = committed.gsub(/(do \|t\|\n)(.*?)(^  end$)/m) { "#{$1}#{$2.lines.reverse.join}#{$3}" }

      assert_not_equal committed, dumped, "#{file} has no create_table block to reorder"
      assert_predicate Update::SchemaOrder.decide(path: file.to_s, clean_before: true, committed:, dumped:), :restore?,
                       "#{file} with its columns reversed was not forgiven"
    end
  end
end
