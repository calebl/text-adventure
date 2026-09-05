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
  #
  # THE PARTY'S OWN BLOW IS NAMED FIRST, which is the captain's reading of
  # 2026-09-05 answered where it is read: he typed `/attack Grenn Ollivar`
  # expecting to ENTER a fight, and it was round 1 -- his blow, then the answer.
  # A round is the turn (call C5), so the player acted first in every round the
  # player opened, and the exchange reads in that order rather than in whatever
  # order `id` happened to give it. Chronological within each side, so two foes
  # still answer in the order they swung.
  def last_exchange
    blows = fight.open_blows
    return [] if blows.empty?

    latest = blows.map(&:round).max
    round = blows.select { |blow| blow.round == latest }

    round.select { |blow| ours?(blow) } + round.reject { |blow| ours?(blow) }
  end

  # THE ROUND THE PANEL IS REPORTING, which is the one BEFORE `#round` and nil
  # before anybody has swung. Off the rows like everything else here.
  def last_round = last_exchange.first&.round

  # WHETHER THE PARTY OPENED THIS FIGHT, out of the first blow nothing has
  # closed. `/attack <name>` IS round 1 -- the captain's ruling of 2026-09-05,
  # option 1 of the three he was offered: *"keep attack as a blow"* -- so when
  # this is true the panel is on the screen BECAUSE the player struck, and
  # `#lead` says so in as many words.
  def opened_by_the_party? = ours?(fight.open_blows.first)

  # THE HEADING: where the fight is, and nothing about what to do. The round
  # belongs on `#call_to_act`, over the buttons, because the round is what the
  # NEXT line lands on and a heading over the condition lines would read as the
  # round they describe.
  def heading = "A fight in #{room.name}."

  # WHAT JUST HAPPENED, IN THE ENGINE'S OWN LINE, AND EVERY CLAUSE IS A ROW.
  #
  # This is the sentence the captain did not have: he struck, the foe answered,
  # and the panel appeared reading `Round 2` with no statement anywhere that
  # round 1 had been fought and that he had fought it. So the boundary is said
  # out loud -- the round that is DONE, who struck whom in it, and, on the first
  # appearance of a fight the party opened, that the fight is on because they
  # struck.
  #
  # THE SECOND SENTENCE IS THE FIRST APPEARANCE ONLY -- round 1 fought, round 2
  # next -- because that is the moment that misread: the panel arrives on the
  # screen for the first time in a fight that exists because the player typed
  # one line. By round 3 the boundary is the only thing left to say and the
  # cause is behind them.
  #
  # Nothing here is invented per render: the names are `Character#fullname`, the
  # round is `Playthrough::Blow#round`, and which side a blow is on is
  # `#ours?` -- the same party `#bodies` is built from.
  def lead
    exchange = last_exchange
    return "No blow has landed yet." if exchange.empty?

    opening = exchange.first.round == 1 && opened_by_the_party?

    [ "Round #{exchange.first.round} is done: #{what_happened(exchange)}.",
      ("The fight is on because you struck." if opening) ].compact.join(" ")
  end

  # WHAT THE BUTTONS UNDER IT ARE: the round the next line lands on, asked as a
  # question, so the row of buttons cannot read as a mode that was entered.
  def call_to_act = "Round #{round}: what do you do?"

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
    @party ||= playthrough.cast_in(room).select { |who| who.is_protagonist? || who.is_companion? }
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
  # THE LABEL SAYS IT IS A BLOW, AND SAYS WHAT DIE. *strike* rather than
  # *attack* because the word on the button is what the player thinks they are
  # about to do, and `d8` because a blow always connects for one die of the
  # attacker's `hit_die` (the captain's call C2) -- so the die IS the whole of
  # what pressing this does. It is `#swing_die` and not a new query: the party's
  # `hit_die` is already on the panel, under every condition line
  # (`Character#max_hp` is derived from it). A body with no stat block gets no
  # parenthesis rather than an invented one, exactly as `Body#state` does.
  def strikes
    foes.map { |who| Action.new(label: strike_label(who), command: "/attack #{who.fullname}") }
  end

  # ONE DIE OF THE PARTY'S OWN `hit_die`, which is what a blow deals
  # (`Playthrough::Turn#damage_for`). Nil for a body written before the stat
  # block columns.
  def swing_die
    die = playthrough.character&.hit_die
    "d#{die}" if die
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

  def strike_label(who) = [ "strike #{who.fullname}", ("(#{swing_die})" if swing_die) ].compact.join(" ")

  # WHOSE BLOW IT IS, against the same party `#bodies` is built from -- the
  # protagonist and their companions, who are wherever the PLAYTHROUGH is.
  def ours?(blow) = blow.present? && party.map(&:id).include?(blow.attacker_id)

  # THE ROUND IN A CLAUSE, and the two sides are told apart because they are
  # different facts: the party ACTED (they typed the line) and the foes
  # ANSWERED (`Playthrough::Riposte` ran on the room the turn began in). When
  # only the foes swung, nobody answered anybody and it is said plainly.
  def what_happened(exchange)
    ours, theirs = exchange.partition { |blow| ours?(blow) }
    return theirs.map { |blow| phrase(blow) }.uniq.to_sentence if ours.empty?

    answer = theirs.any? ? "#{theirs.map { |blow| blow.attacker.fullname }.uniq.to_sentence} answered" : "nobody answered"

    "#{ours.map { |blow| phrase(blow) }.uniq.to_sentence}, and #{answer}"
  end

  def phrase(blow) = "#{name_of(blow.attacker)} struck #{name_of(blow.target)}"

  # THE PROTAGONIST IS *you*, everywhere on this panel -- `Body#mark` already
  # says it of the condition line, and a lead that named the player in the third
  # person would be the `third_person_protagonist` defect `Story::Audit` counts,
  # written by the engine this time.
  def name_of(who) = who.is_protagonist? ? "you" : who.fullname

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
