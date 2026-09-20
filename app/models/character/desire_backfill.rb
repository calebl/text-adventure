# A WANT FOR EVERYBODY WHO WAS WRITTEN BEFORE THERE WERE WANTS.
#
# `Character::StatBackfill`'s twin, and the ONE way in which it is not: that
# one rolls, and this one asks a model. A hit die is the engine's own number
# and `Character::StatBlock` is the only thing that was ever going to decide
# it, so rolling one for an old row is the engine finishing its own job. A
# conscious desire has exactly one author, and it is not the engine.
#
# WHICH IS WHY THIS IS A RAKE TASK AND NOT A STEP IN `Update::REGISTRY`.
# `Update::Step.model_calls?` forbids a post-update step that makes a model
# call, and it is right to: `bin/update` is the one command after a pull and it
# must not be able to spend money or require a key. So this is opt-in, and
# `rake game:backfill_desires` is where it is opted into.
#
# AND WHY IT IS DRY BY DEFAULT, which is the other way it parts company with
# `rake game:backfill_stat_blocks`. That task's dry run is `DRY_RUN=1` because
# a rehearsal and the write produce identical numbers -- the roll is
# deterministic, so there is nothing to be surprised by. This one's rehearsal
# CANNOT be the run: two calls about the same person come back different, so
# what a dry run shows is an example of the answer rather than the answer. A
# task whose preview is not its result should not be the one that runs when
# somebody forgets a flag.
#
# NOBODY IS OVERWRITTEN. A character who already has the four is skipped
# whatever their labels say, on the rule every backfill in this codebase
# keeps: it fills a hole and never revises a decision. A seeded world's own
# `conscious_desire` re-asserts itself over anything here on the next
# `bin/rails db:seed`, which is the file being the decision it always is.
class Character::DesireBackfill
  # WHAT HAPPENED TO ONE PERSON, and it is a value because every consumer only
  # prints. `written` is false on a rehearsal and on a refusal alike; `note`
  # says which.
  Answer = Data.define(:character, :desires, :pursuits, :written, :note) do
    def to_s
      return "#{character.fullname} -- #{note}" if desires.nil?

      "#{character.fullname} (#{pursuits[:desire_pursuit]} / #{pursuits[:need_pursuit]}): " \
        "#{desires[:conscious_desire]}"
    end
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # WHO HAS NONE, oldest first. `#desires?` and not `#pursuits?`: the four are
  # what a model has to be asked for and the two labels come back in the same
  # answer, so somebody holding a label and no sentences is somebody this still
  # has work to do for.
  def pending
    story.characters.order(:id).reject(&:desires?)
  end

  # ONE CALL PER PERSON, AND A REFUSAL IS DROPPED RATHER THAN RAISED.
  #
  # `Character::Registry`'s rule: a story that got wants for four of its five
  # people is a better story than one that threw away four answers over a fifth
  # refusal. The reason lands in the answer and the caller prints it.
  #
  # ONE `save!` PER PERSON and no transaction over the story, for
  # `Playthrough::Volition`'s reason: SQLite has one writer, and a transaction
  # held across a backfill that makes a model call per row is a lock held
  # across a network round trip per row.
  def run(dry_run: true)
    pending.map { |character| write_one(character, dry_run: dry_run) }
  end

  private

  def write_one(character, dry_run:)
    answer = Character::DesireWriter.new(character).generate

    return Answer.new(character: character, desires: answer[:desires], pursuits: answer[:pursuits],
                      written: false, note: nil) if dry_run

    character.assign_attributes(**answer[:desires], **answer[:pursuits])
    character.save!
    Answer.new(character: character, desires: answer[:desires], pursuits: answer[:pursuits],
               written: true, note: nil)
  rescue StandardError => e
    Answer.new(character: character, desires: nil, pursuits: nil, written: false,
               note: "no desires written: #{e.class}: #{e.message}")
  end
end
