# WHICH READER ANSWERED THE LINE THIS TURN CAME OUT OF.
#
# NULLABLE BY HISTORY and for no other reason: every scene written before the
# captain's ruling of 2026-09-04 (evening) was resolved by
# `Playthrough::Classifier`, because there was nothing else to resolve it with,
# and an opening arrival was resolved by nobody at all. `Update::Steps::StampResolvedBy`
# stamps the first of those; the second stays nil for ever, which is the truth
# about it.
#
# A string rather than an enum for the same reason `scenes.resolved_action` is
# one: the closed list lives in code (`Playthrough::Grammar::PATHS`), an enum
# named for one of these values would collide with an ActiveRecord finder, and a
# world here outlives the code that wrote it -- `rake game:doctor` names a value
# outside the list rather than a migration refusing to load the row.
class AddResolvedByToScenes < ActiveRecord::Migration[8.1]
  def change
    add_column :scenes, :resolved_by, :string
  end
end
