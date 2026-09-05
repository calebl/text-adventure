# WHAT THE PLAYER SEES WHEN SOMEBODY IN THE ROOM MEANS THEM HARM, and it is the
# RECORDS RENDERED -- no model call, no narrator, nothing generated and nothing
# written. The captain's call C9, 2026-09-05: ***"go with buttons for now."***
#
# ONE UI, AND THIS IS NOT A SECOND ONE. Every button below posts a fixed command
# string to `TurnsController#create`, exactly as the text box does -- the same
# route, the same `NarrationJob`, the same `Playthrough::Turn#play`. The strings
# are SLASHED (`/attack Marek Sollen`), which is the captain's ruling of
# 2026-09-05 -- *"I think we should only auto accept the slash commands"* --
# used for what it was built for: a slashed line is read by
# `Playthrough::Grammar` and never by the classifier, so pressing a button costs
# ZERO MODEL CALLS. A player who would rather type the same line still can; the
# box is still under the panel.
#
# THERE IS NO BATTLE FLAG AND THERE IS NO BATTLE MODE. A fight is on when
# `Playthrough#foes_in` answers with somebody, which is a query over
# `characters.hostile` and this game's `playthrough_vitals.provoked_at` -- the
# same reader `Playthrough::Riposte` swings with and `Playthrough::Fight` closes
# on. So the panel appears when the engine says there is a fight and disappears
# when it says there is not, and there is nothing to reconcile in either
# direction: the last foe dies, or the party walks out, and the ordinary prose
# loop resumes because it never stopped.
#
# WHY IT IS A CLASS AND NOT ERB. It is the one author of what the panel says,
# for `Playthrough::Refusal`'s and `Playthrough::DeathNotice`'s reason: the
# words and the numbers a player reads come out of one place that can be tested
# without a browser. The view renders what this answers and decides nothing.
#
# WHAT IS DELIBERATELY NOT HERE. No hit-point BAR -- condition lines, `2 of 6`,
# in the house `.notice` grey, because the reading experience is its own stage
# (`ta-api-iface`) and a new visual vocabulary invented in a battle panel is
# that stage arriving early (the scout's §12.2 cost 3, §15.6). No prose per
# round: that is shape (b), it needs `ta-prompt-bench`, and the bench does not
# exist yet. No throw buttons -- the verb exists now and the button does not:
# see `#throws`.
class Playthrough::Battle
  # ONE LINE ABOUT ONE BODY, and every one of them is a record read back.
  #
  # `state` is the numbers and never an adjective, which is the rule
  # `Playthrough::Vitals::Condition#in_words` is written under -- *"hurt" alone
  # is a mood and "4 of 11" is a fact"* -- taken one step further, because in a
  # fight the number is the whole of what a player is deciding on. A body with
  # no stat block says so rather than being given one: that state is a
  # `rake game:doctor` finding and not something a view invents around.
  Body = Data.define(:character, :condition, :mark) do
    def name = character.fullname
    def state = condition ? "#{condition.hp} of #{condition.max}" : "no stat block"
  end

  # A BUTTON: what it says, and the line it posts. The line is the whole of the
  # button -- there is no other payload and no other route -- which is what
  # makes this panel a shortcut into the one loop rather than a second way in.
  Action = Data.define(:label, :command)

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # WHETHER THERE IS A FIGHT, DERIVED AND NEVER STORED. A game that is over is
  # not in one whatever is standing in the room: the player is dead, nothing
  # will change again, and `Playthrough::DeathNotice` has the screen.
  def on? = !playthrough.over? && foes.any?

  def room = playthrough.current_location

  def foes = @foes ||= playthrough.foes_in(room)

  def fight = @fight ||= Playthrough::Fight.new(playthrough)

  # WHICH ROUND THE NEXT LINE LANDS ON, out of `Playthrough::Fight` and off the
  # rows -- the same number `Playthrough::Turn#play` hands every blow of the
  # turn. 1 when nobody has swung yet, which is what a room you have only just
  # walked into reads.
  def round = fight.next_round

  # THE BLOWS OF THE LAST ROUND FOUGHT, and only that round: the panel says what
  # just happened, and the whole exchange is in the log once the fight closes
  # (`Playthrough::Fight#sentence`). Empty before the first swing.
  def last_exchange
    blows = fight.open_blows
    return [] if blows.empty?

    latest = blows.map(&:round).max
    blows.select { |blow| blow.round == latest }
  end

  # ONE CONDITION LINE PER BODY IN THE FIGHT: the party first, then the foes.
  #
  # The party is `Playthrough#cast_in` filtered to the protagonist and their
  # companions rather than a new reader -- the party is derived and always will
  # be (they are wherever the PLAYTHROUGH is), and `#cast_in` is where that is
  # already written down. Bystanders are not here on purpose: this is who is in
  # the fight, and a name on it that nobody can swing at or be swung at by would
  # read as a combatant.
  def bodies
    party.map { |who| Body.new(character: who, condition: playthrough.vitals_for(who), mark: mark_for(who)) } +
      foes.map { |who| Body.new(character: who, condition: playthrough.vitals_for(who), mark: mark_for(who)) }
  end

  def party
    playthrough.cast_in(room).select { |who| who.is_protagonist? || who.is_companion? }
  end

  # A BLOW AT EACH LIVE FOE. The dead are already out of `#foes_in` -- it reads
  # `Playthrough#cast_in`, which subtracts this game's dead -- so there is no
  # separate liveness test here and no way for the panel to offer a corpse a
  # fight.
  #
  # It offers the FOES and not everybody standing here, though
  # `Playthrough::Classifier#offered_for(:attack)` is the wider set (the
  # captain's sixth ruling of 2026-09-05, *"anyone can be attacked"*). Both are
  # true at once: a player may still TYPE `/attack Grenn Ollivar` and the engine
  # will play it. What a button does is offer the act the panel is about, and
  # putting a bystander on a row of strike buttons would be the app suggesting
  # it.
  def strikes
    foes.map { |who| Action.new(label: "strike #{who.fullname}", command: "/attack #{who.fullname}") }
  end

  # THE WAY OUT, WHICH IS ALWAYS THERE -- the captain's call C1: a fight is
  # always escapable by leaving the room, with a price. The foes in the room you
  # LEFT strike once before you go (`Playthrough::Riposte` runs on the room the
  # turn BEGAN in), and then the fight is over and `Playthrough::Fight#close!`
  # writes the one Scene that says so.
  #
  # This is the one button on the panel that costs a model call, and it costs it
  # for the ordinary reason: walking somewhere realizes it and narrates arriving
  # (`Playthrough::Turn#move_to`). Leaving a fight is a move like any other move.
  def ways_out
    playthrough.exits.map { |exit| Action.new(label: "go to #{exit.name}", command: "/go #{exit.name}") }
  end

  # THE SLICE 5 SEAM, AND IT IS STILL EMPTY -- BUT NO LONGER FOR ITS ORIGINAL
  # REASON.
  #
  # The verb HAS landed (`ta-combat-throw`): `throw` is in
  # `Playthrough::Grammar::VERBS` and `ENGINE_VIEW`, `Item::BULK` exists, and
  # `Playthrough::Turn#throw_item!` is the writer. So a button here would post a
  # line the engine reads, which is what this seam was waiting for. What it is
  # waiting for NOW is somebody's decision to render it: a throw button is a
  # PANEL change, and the slice that shipped the verb deliberately did not make
  # one (its brief put the panel out of scope, and this file is the panel's).
  #
  # WHAT TO DO, and the shape is settled rather than guessed at now: give each
  # thing the party is carrying (`Playthrough#carried`) one button per live foe,
  # labelled `throw the ward stamp at Marek Sollen` and posting exactly that
  # behind a slash -- `/throw <thing> at <name>`, because the verb reads TWO
  # names out of two closed sets and `Playthrough::IntentSchema` was left alone
  # (the captain's call C6). The command may also name a thing LYING here, since
  # the lift is part of the throw. Render them between `#strikes` and
  # `#ways_out`; `_battle.html.erb` already has the row.
  #
  # ONE THING THE BUTTONS WILL HAVE TO SAY that a strike does not: an
  # `immovable` thing cannot be thrown at all and the engine refuses the line
  # (`Playthrough::Refusal`'s `:immovable`), so either the offer is narrowed to
  # `Item#throwable?` or the player gets a button that always refuses.
  def throws = []

  private

  # WHY THIS BODY IS ON THE PANEL, in one word, and each word is a different
  # record. `hostile` is the WORLD's -- a seed file wrote it and no typed line
  # can move it (`EngineSweep::Invariants#hostility_unmoved`); `provoked` is
  # THIS GAME's -- `playthrough_vitals.provoked_at`, written when the party
  # swung first. The world's answer is given first when both are true, because
  # it is the one that was true before anybody played.
  def mark_for(who)
    return "you" if who.is_protagonist?
    return "with you" if who.is_companion?
    return "hostile" if who.hostile?
    return "provoked" if playthrough.provoked?(who)

    nil
  end
end
