class StoreWhatThePlayerTyped < ActiveRecord::Migration[8.1]
  # WHAT THE PLAYER TYPED, as a column on the turn it produced.
  #
  # `interactions.user_input` was the only field holding it, and interactions
  # only exist on the talk branch -- so a narrated or arriving turn kept no
  # record of the line that caused it. `Playthrough::Debug` reconstructed it by
  # scraping the classifier's stored prompt, which works only while that
  # conversation is still kept: the audit trail is pruned at
  # `Chat::KEEP_TURNS`, so on an older turn the player's own words vanished.
  #
  # A `Scene` is the one thing every branch of the loop produces, so that is
  # where it belongs.
  def up
    add_column :scenes, :typed, :text

    # BACKFILL WHAT IS STILL RECOVERABLE, from the two places that have it.
    # Interactions first, because that is a real column and the exact string;
    # then the classifier prompts that have not been pruned yet, which is where
    # the debug view was already reading from. Raw SQL rather than the models:
    # a migration must not depend on app code that may have moved on.
    say_with_time "backfilling scenes.typed from interactions.user_input" do
      execute <<~SQL.squish
        UPDATE scenes SET typed = (
          SELECT i.user_input FROM interactions i
          WHERE i.scene_id = scenes.id AND i.user_input IS NOT NULL AND i.user_input != ''
          ORDER BY i.id LIMIT 1
        )
        WHERE typed IS NULL
      SQL
    end

    # The classifier's prompt ends with the raw line under a fixed heading (see
    # `Playthrough::Classifier#command_prompt`). SQLite has no regex, so this is
    # `substr` after `instr` -- and it takes everything to the end of the
    # prompt, which is where that heading's section runs to.
    say_with_time "backfilling scenes.typed from unpruned classifier prompts" do
      execute <<~SQL.squish
        UPDATE scenes SET typed = TRIM((
          SELECT substr(m.content, instr(m.content, '## The Player Types' || char(10)) + 20)
          FROM messages m
          JOIN chats c ON c.id = m.chat_id
          WHERE m.scene_id = scenes.id AND c.purpose = 'classifier' AND m.role = 'user'
            AND instr(m.content, '## The Player Types' || char(10)) > 0
          ORDER BY m.id LIMIT 1
        ))
        WHERE typed IS NULL
      SQL
    end

    execute "UPDATE scenes SET typed = NULL WHERE typed = ''"
  end

  def down
    remove_column :scenes, :typed
  end
end
