# WHICH VERSION OF THE PROSE INSTRUCTIONS THE JUDGED TURN WAS WRITTEN UNDER.
#
# `Playthrough::Feedback` already freezes which model wrote a turn; this is the
# other half of the same question, and the ROADMAP's `ta-prompt-bench` entry
# asks for it by name. Nullable, and it stays nullable: every verdict recorded
# before this column existed has no answer, and a backfill would have to guess
# at what the file said on the day.
class AddProsePromptDigestToPlaythroughFeedbacks < ActiveRecord::Migration[8.1]
  def change
    add_column :playthrough_feedbacks, :prose_prompt_digest, :string
    add_index :playthrough_feedbacks, :prose_prompt_digest
  end
end
