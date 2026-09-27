# WHAT THE PLAYER CAN DO FROM HERE, verb by verb, and why not when they cannot.
#
# For every verb in the closed set a typed line can resolve to
# (`Playthrough::IntentSchema::INTENTS`, less `other`, which names nothing),
# this answers three things: whether the verb is available, the reason when it
# is not, and the closed set of targets it can take. A front end reads it to
# draw a panel or offer a completion; it never decides anything itself.
#
# THE TARGETS ARE THE ENGINE'S, FILTERED BY THE ENGINE'S OWN CHECK. Each
# candidate comes out of `Playthrough::Classifier#offered_for` -- the same set a
# model is offered and the grammar resolves against -- and is then kept only if
# `Playthrough::Turn#refusal_for` would play an intent naming it. So a target
# this lists is one the engine accepts, by construction rather than by a second
# copy of its rules: an immovable thing is not offered to `take`, a locked way
# out is not offered to `move`, and the dead are not offered to anybody because
# `Playthrough#cast_in` already leaves them out.
#
# THE REASON IS THE ENGINE'S WORDS. A finished game says
# `Playthrough::EndNotice#sentence`; a game with no hands or no floor says what
# `Playthrough::Refusal.unplayable` says; an empty set says
# `Playthrough::Refusal::EMPTY`'s sentence. No wording is authored here.
#
# NOT "AFFORDANCES". That word already names the physical-action parameters on
# items and passages (the migration that added `use_kind`, barriers and
# passage states); this class reads those through `Playthrough::PhysicalAction`
# for the `use` verb and does not rename them.
#
# It reads records only: it writes nothing, calls no model and rolls no die.
# The engine's own instruments (`harm`, `mend`, `check`) are not verbs in the
# fiction and are not listed.
class Playthrough::Availability
  VERBS = %i[move talk examine take drop attack throw use].freeze

  # ONE VERB. `targets` is the closed set, in the order the engine offers it;
  # `aims` is set only for `throw`, the one verb that names two records.
  # `reason` is nil exactly when the verb is available.
  Verb = Data.define(:name, :targets, :aims, :reason) do
    def initialize(aims: nil, reason: nil, **rest) = super
    def available? = reason.nil?
  end

  REASONS = {
    examine: "There is nothing here or in your hands to look at closely.",
    throw: "There is nothing you can lift and nothing to throw it at."
  }.freeze

  attr_reader :playthrough

  def initialize(playthrough, classifier: nil)
    @playthrough = playthrough
    @classifier = classifier
  end

  def verbs = VERBS.map { |name| verb(name) }

  def verb(name)
    name = name.to_sym
    return Verb.new(name: name, targets: [], aims: (name == :throw ? [] : nil), reason: over_reason) if playthrough.over?

    send(:"#{name}_verb")
  end

  def to_h = verbs.index_by(&:name)

  # THE ONE CHECK every target passes: the engine would play an intent naming
  # it. Public so the test can hold every offered target to it.
  def accepted?(intent) = !intent.refused? && turn.refusal_for(intent, "").nil?

  def classifier = @classifier ||= Playthrough::Classifier.new(playthrough)

  private

  def move_verb = single(:move, :destination)
  def talk_verb = single(:talk, :speaker)
  def examine_verb = single(:examine, :item)
  def take_verb = single(:take, :item)
  def drop_verb = single(:drop, :item)
  def attack_verb = single(:attack, :speaker)

  def single(name, slot)
    targets = classifier.offered_for(name).select do |record|
      accepted?(Playthrough::Classifier::Intent.new(action: name, slot => record))
    end
    Verb.new(name: name, targets: targets, reason: (blocked(name) if targets.empty?))
  end

  # THE THING OUT OF BOTH ITEM SETS AND THE AIM OUT OF WHO IS HERE AND THE WAYS
  # OUT, the sets `Playthrough::Grammar#read_throw` resolves each half against.
  # A thing is kept if some aim takes it and an aim if some thing reaches it;
  # the engine's gate only refuses on the thing (it does not move) or the aim (a
  # shut way), so every pair of what is kept is accepted.
  def throw_verb
    things = classifier.items_carried + classifier.items_here
    aims = classifier.characters_here + classifier.exits_here
    pairs = things.product(aims).select do |thing, aim|
      accepted?(Playthrough::Classifier::Intent.new(action: :throw, item: thing, at: aim))
    end
    targets = pairs.map(&:first).uniq
    kept_aims = pairs.map(&:last).uniq
    Verb.new(name: :throw, targets: targets, aims: kept_aims, reason: (blocked(:throw) if targets.empty?))
  end

  # THE CLOSED ATTEMPTS, as `Playthrough::PhysicalAction` builds them for this
  # room and these hands. A target here is a `Choice`; its `token` is what a
  # front end sends back.
  def use_verb
    targets = classifier.offered_for(:use).select do |choice|
      accepted?(Playthrough::Classifier::Intent.new(action: :use, physical: choice))
    end
    Verb.new(name: :use, targets: targets, reason: (blocked(:use) if targets.empty?))
  end

  def blocked(name)
    unplayable = Playthrough::Refusal.unplayable(Playthrough::Classifier::Intent.new(action: name),
                                                 playthrough: playthrough, typed: "")
    unplayable&.fact || Playthrough::Refusal::EMPTY[name] || REASONS.fetch(name)
  end

  def over_reason = Playthrough::EndNotice.for(playthrough).sentence

  def turn = @turn ||= Playthrough::Turn.new(playthrough)
end
