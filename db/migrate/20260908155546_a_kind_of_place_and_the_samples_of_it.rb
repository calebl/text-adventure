# A KIND OF PLACE THE CAPTAIN TYPED, AND EVERY DRAW OF IT.
#
# `Lab::Realization`'s header is the design and says why a lab is not a bench;
# what belongs here is why the two tables have the shape they have.
#
# TWO TABLES AND NOT THREE. A sample has at most one verdict, so the verdict is
# columns on the sample rather than a table of its own --
# `Playthrough::Feedback` is a separate table because a scene may have no
# verdict and the verdict has to carry its own stamps of what produced the
# prose, and a lab sample already carries those on `row`.
#
# THE EXPECTATION IS COLUMNS ON THE KIND, one per pick, each a comma-joined set
# of allowed labels -- `Playthrough::Drift#offered`'s shape and
# `Playthrough::Feedback#prose_models`', chosen for their reason: the value is
# read by a person, grouped in Ruby, and never queried into. NULL is not an
# empty set: it is *don't care*, which takes the kind out of that figure's
# numerator and denominator both (`Eval::Realization::Corpus`'s `expects_inside`
# rule, one level up). A default of "" would erase the difference between a
# captain who said nothing and one who allowed nothing.
#
# AND THE SAMPLE KEEPS THE WHOLE STORED ROW AND NOTHING DERIVED FROM IT. `row`
# is `Eval::Realization::Bench::Reading#to_h` -- the prompts as sent, both raw
# answers, the facts the world held before the call, and what the registries
# made of it. The flags, the picks, the tokens and the latency are all read back
# off it by `Eval::Realization::Scorer`, offline and for nothing, so a column
# for any of them would be a second record that could disagree with the first.
#
# NO INDEX ON THE VERDICT. `Playthrough::Feedback` has one because the scoreboard
# groups every turn in the database by it; a kind has tens of samples and they
# are read as a list. An index nothing queries is a write cost with no reader.
class AKindOfPlaceAndTheSamplesOfIt < ActiveRecord::Migration[8.1]
  def change
    create_table :lab_realization_kinds do |t|
      # WHICH WORLD, BY TITLE AND NOT BY ROW. A kind is realized on a copy of a
      # world put back from its seed file and rolled back afterwards
      # (`Eval::Realization::Stage`), so there is no `Story` for it to belong
      # to -- and a kind that pointed at one would go stale the moment somebody
      # played it. The title is the file's own key (`Eval::Realization.world_file`).
      t.string :world, null: false
      t.string :name, null: false
      t.text :teaser, null: false

      # THE FACTS A REAL EXITS CALL WOULD HAVE SUPPLIED, each nullable because
      # each is honestly absent on an ordinary kind: no way back (an opening
      # room), no inside (a road, a clearing), no danger said (the engine rolls
      # one) and no population word (the engine rolls one at realization).
      t.string :reached_from
      t.string :inside
      t.string :danger
      t.string :population

      # WHAT HE SAYS THE PICKS SHOULD BE. See the header for why NULL and "" are
      # different states.
      t.text :expects_inside
      t.text :expects_population
      t.text :expects_storeys_above
      t.text :expects_storeys_below
      t.text :expects_danger
      t.text :expects_gradient
      t.text :expects_hazard

      t.timestamps
    end

    create_table :lab_realization_samples do |t|
      t.references :kind, null: false, foreign_key: { to_table: :lab_realization_kinds }
      t.json :row, null: false, default: {}

      # HIS JUDGEMENT, AND A SAMPLE MAY HAVE NONE. A drawn sample is a record
      # whether or not he has looked at it, so the verdict is nullable and the
      # aspects are a comma-joined set of which parts he meant -- zero of them
      # is a complete answer.
      t.string :verdict
      t.text :aspects
      t.text :note

      t.timestamps
    end
  end
end
