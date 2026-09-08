class AnEventGetsAnHourAndAQuestGetsMoreThanOneEnd < ActiveRecord::Migration[8.1]
  def change
    # THE SECOND HALF OF CALL 8, 2026-09-06: *"some events will need to happen
    # at a particular time, like if we have story where a bomb is going to go
    # off or a volcano is going to explode 1 week in the future."*
    #
    # TWO COLUMNS BECAUSE THERE ARE TWO MOMENTS AND THEY MEAN DIFFERENT THINGS.
    # `occurred_at` already exists and is the moment on the story clock the row
    # was RECORDED. `scheduled_for` is the moment the thing is DUE, and it is
    # what makes a row a statement about the future rather than about the past.
    # `fired_at` is the moment the engine actually fired it -- not a boolean,
    # because the gap between due and fired is the thing a person reading the
    # stream wants to see. See `WorldEvent`.
    add_column :world_events, :scheduled_for, :datetime
    add_column :world_events, :fired_at, :datetime
    # THE DUE LOOKUP, WHICH RUNS ON EVERY TURN. `Story#catch_up_world!` asks for
    # this story's unfired rows at or before the clock, so the index is the two
    # columns that question is asked on.
    add_index :world_events, [ :story_id, :scheduled_for ]

    # WHICH OF SEVERAL ENDINGS ONE GAME REACHES, decided by the engine off
    # records. `condition` is a key into `Quest::Outcome::CONDITIONS` -- a
    # closed table of rules, in `Quest::TRIGGERS`' shape -- and `minutes` is the
    # one number a rule may take, spelled the way `quest_steps.minutes` is
    # because it means the same thing: whole story minutes.
    #
    # NULL IS THE ORDINARY ANSWER and it means *nothing selects this ending*.
    # The default outcome is reached by falling through, so it carries no
    # condition; a NON-default one that carries none is an ending no path can
    # reach, which `Story::Doctor` reports.
    add_column :quest_outcomes, :condition, :string
    add_column :quest_outcomes, :minutes, :integer

    # AND WHAT THE WORLD DOES ABOUT IT LATER -- the *"future ramifications"* of
    # 2026-09-06, as the smallest thing that can be one: an outcome may put ONE
    # scheduled row on the stream, `ramification_minutes` after the ending, with
    # `ramification_summary` as its sentence. Both or neither.
    add_column :quest_outcomes, :ramification_summary, :text
    add_column :quest_outcomes, :ramification_minutes, :integer

    # NOTHING IS BACKFILLED, AND THAT IS A DECISION RATHER THAN AN OMISSION.
    # Every new column here is legitimately null on every row that exists: an
    # event written before today is a thing that HAS happened, so it has no due
    # hour and never fired, and an ending written before today was reached by
    # falling through, so it has no condition. The one state this leaves that a
    # reader should know about -- a non-default outcome nothing can now select
    # -- is a report (`Story::Doctor`'s `outcome_nothing_can_reach`) and not a
    # value this migration could honestly invent: which rule its author meant is
    # not on record, and backfilling world data to make a check pass is the one
    # thing that tool's own rule forbids.
  end
end
