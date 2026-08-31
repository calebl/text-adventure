# `transgender` was one enum value standing in for two different people, and it
# carried no pronoun rule anywhere. It is now `trans_woman` and `trans_man`,
# which take she/her/hers and he/him/his -- the same pronouns as any other woman
# or man.
#
# An existing `transgender` row says nothing about which of the two the person
# is: the column is the only record of it. Rather than guess silently, every
# affected row is moved to `trans woman` and logged by id, so a human can
# correct the ones that are wrong. The alternatives are worse: dropping the row
# deletes a character, and blanking `sex` fails Character's presence validation,
# leaving a record that cannot be saved again.
#
# `sex` is a plain string column, so this is UPDATEs, not a schema change.
class SplitTransgenderIntoTransWomanAndTransMan < ActiveRecord::Migration[8.0]
  def up
    affected = select_values("SELECT id FROM characters WHERE sex = 'transgender'")

    if affected.any?
      say "Moving #{affected.size} character(s) from 'transgender' to 'trans woman': " \
          "ids #{affected.join(", ")}. Which of trans woman / trans man each " \
          "person is was never recorded, so review these by hand."
    end

    execute "UPDATE characters SET sex = 'trans woman' WHERE sex = 'transgender'"
  end

  # Both new values collapse back to the single value they replaced, which is
  # exactly the information loss this migration exists to undo.
  def down
    execute "UPDATE characters SET sex = 'transgender' WHERE sex IN ('trans woman', 'trans man')"
  end
end
