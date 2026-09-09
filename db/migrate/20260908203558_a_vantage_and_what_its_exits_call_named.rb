# THE EXITS LAB'S THREE TABLES. `Lab::Exits`'s header is the design and the
# captain's seven answers of 2026-09-08; what belongs here is why each column is
# the shape it is.
#
# `absent` IS NEWLINE-SEPARATED AND NOT COMMA-SEPARATED, which is the one place
# this departs from `Lab::Realization::Kind`'s stored lists. That file joins on a
# comma and its header says why it may: no label in any of the closed lists holds
# one. These are PLACE NAMES, and a world in the corpus already holds
# `Grenn's Boarding House, Room 3` -- so a comma-joined list of them would split
# one place into two, and the two halves would each be a name no world has.
#
# `expects_population` IS comma-separated, because it holds labels off
# `Location::Population::LABELS` and that argument still applies to it.
class AVantageAndWhatItsExitsCallNamed < ActiveRecord::Migration[8.1]
  def change
    # WHAT HE TYPES: a place the model will be asked to name the ways out of.
    #
    # THERE IS NO `inside` COLUMN AND ITS ABSENCE IS THE POINT. A vantage with an
    # `inside` band becomes a laid-out place, and `Location::Generator#write_exits!`
    # returns early on one -- so a vantage that could carry a band would be a
    # vantage that could silently cancel the only call this lab measures. Not
    # validated against; made unreachable.
    create_table :lab_exits_vantages do |t|
      t.string :world, null: false
      t.string :name, null: false
      t.text :teaser, null: false
      t.string :reached_from
      t.string :danger
      t.text :absent

      # HIS EXPECTATION, IN TWO SHAPES, which is the captain's Call 4 answered
      # (c): a quantifier over the whole answer, and a per-name expectation on
      # the `lab_exits_judgements` rows below.
      t.string :expects_inside_quantifier
      t.text :expects_population

      t.timestamps
    end

    # ONE DRAW. `row` is `Eval::Realization::Bench::Reading#to_h`, the same
    # column and the same shape as `lab_realization_samples.row`, because it is
    # the same runner and the same reading -- see `Lab::Exits::Runner`.
    create_table :lab_exits_samples do |t|
      t.references :vantage, null: false, foreign_key: { to_table: :lab_exits_vantages }
      t.json :row, null: false, default: {}
      t.string :verdict
      t.text :aspects
      t.text :note

      t.timestamps
    end

    # ONE PLACE THIS VANTAGE NAMES, and the row that carries both halves of what
    # he says about it: the expectation he typed BEFORE a draw and the verdict he
    # gave AFTER one. `Lab::Exits::Judgement`'s header draws the line between
    # them and says why they share a row rather than a table each.
    #
    # `name_key` IS `WorldSeed.natural_key` AND IS WHAT IDENTITY MEANS HERE.
    # `name` is what was typed or what the model said, kept so the page can print
    # it; the key is what two mentions of one place agree on. That is the repo's
    # one spelling of "the same name written differently" and since
    # `Location::Generator#find_location` resolves through it, a judgement and the
    # engine cannot disagree about which place a name meant.
    create_table :lab_exits_judgements do |t|
      t.references :vantage, null: false, foreign_key: { to_table: :lab_exits_vantages }
      t.string :name, null: false
      t.string :name_key, null: false
      t.text :expects_inside
      t.text :expects_population
      t.string :verdict
      t.text :aspects
      t.text :note

      t.timestamps

      # ONE ROW PER PLACE PER VANTAGE, enforced here rather than only in Ruby:
      # `#record!` finds-or-creates on this pair, so a second row would make one
      # place's expectation and one place's verdict land on different rows and
      # the hit rate would read whichever it found first.
      t.index %i[vantage_id name_key], unique: true, name: "index_lab_exits_judgements_on_place"
    end
  end
end
