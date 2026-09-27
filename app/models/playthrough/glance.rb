# WHAT A FRONT END'S SIDE PANELS SHOW, for the room the player stands in.
#
# One reader, so every front end draws the same panels from the same records:
# the room and its ways out, the people here and how each of them is, what is
# lying here, what the player carries, the player's condition, the story's next
# beat, and -- through `Playthrough::Availability` -- which verbs are open, why
# the others are not, and what each can be aimed at.
#
# IT REUSES THE READ-OUT, IT DOES NOT COPY IT. `Playthrough::Mechanics#state` is
# already the engine's view after a line; this reads that `State` (building a
# `Mechanics` makes no model call) and adds only what the console does not
# print: the containing place, whether each way out is written and open, the
# next beat the narrator is told (`Playthrough::Moment#next_beat` reads the same
# `Playthrough::Arc#next_step`), the story's clock for this game and the
# availability of each verb. The console read-out stays as it was, because the
# sweep asserts on it.
#
# It reads records only: it writes nothing, calls no model and rolls no die.
# `Playthrough::Session#glance` is how a front end asks for it.
class Playthrough::Glance
  Exit = Data.define(:location, :written, :open) do
    def name = location.name
  end

  Person = Data.define(:character, :condition, :foe, :provoked) do
    def name = character.fullname
  end

  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  def location = state.location
  def containing_place = location&.containing_place
  def items_here = state.items_here
  def carried = state.carried
  def condition = state.condition
  def sheet = state.sheet
  def over? = state.over
  def story_now = playthrough.story_now

  def exits
    state.exits.map do |exit|
      edge = LocationConnection.walked(location, exit)
      Exit.new(location: exit, written: !exit.stub?, open: edge.nil? || edge.open_for?(playthrough))
    end
  end

  def people
    state.present.map do |who|
      Person.new(character: who, condition: state.conditions[who.id],
                 foe: state.foes.include?(who), provoked: state.provoked.include?(who))
    end
  end

  # THE SENTENCE THE NARRATOR IS TOLD THE STORY IS ASKING FOR, or nil for a
  # world with no arc and for one whose arc is walked to its end.
  def next_beat = Playthrough::Arc.new(playthrough).next_step&.summary

  # WHY THE GAME STOPPED, in the words the play page and the refusal use, or nil
  # for a game still being played.
  def ended = (Playthrough::EndNotice.for(playthrough).sentence if over?)

  def verbs = availability.verbs
  def verb(name) = availability.verb(name)

  # THE SAME PANELS AS PLAIN LINES, for `rake game:mechanics`' `glance`. Names
  # only; ids and formatting beyond that are a front end's business.
  def to_s
    [
      "  room        #{location ? location.name : "nowhere"}#{" (in #{containing_place.name})" if containing_place}",
      line("ways out", exits.map { |exit| "#{exit.name}#{" [unwritten]" unless exit.written}#{" [shut]" unless exit.open}" }, "none"),
      line("people", people.map { |person| [ person.name, person.condition&.in_words, ("foe" if person.foe) ].compact.join(", ") }, "nobody else", "; "),
      line("lying here", items_here.map(&:name), "nothing"),
      line("carrying", carried.map(&:name), "nothing"),
      line("condition", [ condition&.in_words, *sheet ].compact, "no stat block", "; "),
      "  next beat   #{next_beat || "this world has no arc"}",
      *("  ended       #{ended}" if ended),
      *verbs.map { |verb| verb_line(verb) }
    ].join("\n")
  end

  private

  def state = @state ||= Playthrough::Mechanics.new(playthrough, model: false).state

  def availability = @availability ||= Playthrough::Availability.new(playthrough)

  def line(label, values, empty, separator = ", ")
    format("  %-11s %s", label, values.presence&.join(separator) || empty)
  end

  def verb_line(verb)
    return format("  %-11s blocked -- %s", verb.name, verb.reason) unless verb.available?

    names = verb.targets.map { |target| target.respond_to?(:token) ? target.name : Playthrough::Classifier.label_for(target) }
    aims = verb.aims && " at #{verb.aims.map { |aim| Playthrough::Classifier.label_for(aim) }.join(", ")}"
    format("  %-11s %s%s", verb.name, names.join(", "), aims)
  end
end
