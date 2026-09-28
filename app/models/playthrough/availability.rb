# WHAT THE PLAYER CAN DO FROM HERE, verb by verb, and why not when they cannot.
#
# For every verb in the closed set a typed line can resolve to, less `other`,
# which names nothing, this answers three things: whether the verb is
# available, the reason when it is not, and the closed set of targets it can
# take. A front end reads it to draw a panel or offer a completion; it never
# decides anything itself.
#
# THE ENGINE ANSWERS IT. The Rust engine plays every turn, so the targets are
# the engine's: each candidate out of the closed set a line reads against, kept
# only where the engine's own refusal check would play an intent naming it. So
# the panel cannot offer a target the engine then refuses. The reason is the
# engine's words too -- the end notice's sentence for a finished game, the
# refusal's for a game with no hands or no floor or an empty set. This holds
# `Playthrough::RustEngine.glance`'s `verbs` as values, and authors none of it.
#
# NOT "AFFORDANCES". That word already names the physical-action parameters on
# items and passages (the migration that added `use_kind`, barriers and
# passage states); the `use` verb's targets are those attempts, and this does
# not rename them.
#
# The engine's own instruments (`harm`, `mend`, `check`) are not verbs in the
# fiction and are not listed.
class Playthrough::Availability
  # ONE TARGET: a record by id and the name a player types for it, or, for
  # `use`, one whole attempt -- its `use:` token, its own word, and the line
  # that plays it (nil where no line the grammar reads plays this attempt rather
  # than another one of the same name).
  Target = Data.define(:id, :name, :token, :kind, :line) do
    def initialize(id: nil, token: nil, kind: nil, line: nil, **rest) = super
  end

  # ONE VERB. `targets` is the closed set, in the order the engine offers it;
  # `aims` is set only for `throw`, the one verb that names two records.
  # `reason` is nil exactly when the verb is available; `word` is what follows
  # the slash for it, nil for `use`, whose attempts each have their own.
  Verb = Data.define(:name, :targets, :aims, :reason, :word) do
    def available? = reason.nil?
  end

  attr_reader :playthrough

  def initialize(playthrough, document = Playthrough::RustEngine.glance(playthrough))
    @playthrough = playthrough
    @document = document
  end

  def verbs = @verbs ||= @document["verbs"].map { |verb| verb_of(verb) }

  def verb(name) = verbs.find { |verb| verb.name == name.to_sym }

  def to_h = verbs.index_by(&:name)

  private

  def verb_of(verb)
    Verb.new(name: verb["name"].to_sym, targets: verb["targets"].map { |target| target_of(target) },
             aims: verb["aims"]&.map { |aim| target_of(aim) }, reason: verb["reason"], word: verb["word"])
  end

  def target_of(target) = Target.new(**target.transform_keys(&:to_sym))
end
