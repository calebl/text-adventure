# WHAT A FRONT END'S SIDE PANELS SHOW, for the room the player stands in.
#
# One reader, so every front end draws the same panels from the same records:
# the room and its ways out, the people here and how each of them is, what
# stands here fixed in place and what lies on or in it, what is lying here, what
# the player carries, the player's condition, the story's next
# beat, and -- through `Playthrough::Availability` -- which verbs are open, why
# the others are not, and what each can be aimed at.
#
# THE ENGINE READS IT. The Rust engine plays every turn, so it is also the one
# that says what the panels show between turns: `Playthrough::RustEngine.glance`
# hands back its document, and this holds that document as values -- ids,
# names and the engine's own sentences, never a record. So the verbs a panel
# offers are the ones the engine plays, by the engine's own check, rather than
# a second copy of its rules beside it. `Playthrough::Mechanics::State` is a
# separate reader of the same rows in Ruby, kept for the judges that compare
# the two (`EngineSweep::Dump`).
#
# It reads records only: it writes nothing, calls no model and rolls no die.
# `Playthrough::Session#glance` is how a front end asks for it.
class Playthrough::Glance
  Room = Data.define(:id, :name, :within)
  Exit = Data.define(:id, :name, :written, :open)
  Person = Data.define(:id, :name, :condition, :foe, :provoked)
  # `on` is the fixture a thing lies on or in, by name, or nil.
  Thing = Data.define(:id, :name, :on)
  # Something fixed in place: `holds` is one of `Item::HOLDS`, `state` and
  # `searched` are nil for a fixture with no inside, and `on` is what lies on
  # or in it, by name.
  Fixture = Data.define(:id, :name, :holds, :state, :searched, :on)
  # How much the room shows, and how many closed fixtures nobody has searched.
  Counts = Data.define(:visible, :unsearched)

  attr_reader :playthrough, :document

  def initialize(playthrough, document = Playthrough::RustEngine.glance(playthrough))
    @playthrough = playthrough
    @document = document
  end

  def room = (Room.new(**fields(document["room"])) if document["room"])
  def exits = document["exits"].map { |exit| Exit.new(**fields(exit)) }
  def people = document["people"].map { |person| Person.new(**fields(person)) }
  def fixtures = document["fixtures"].map { |fixture| Fixture.new(**fields(fixture)) }
  def lying_here = document["lying_here"].map { |thing| Thing.new(**fields(thing)) }
  def counts = Counts.new(**fields(document["counts"]))
  def carrying = document["carrying"].map { |thing| Thing.new(**fields(thing)) }

  # The player's condition in words (`Playthrough::Vitals::Condition#in_words`),
  # nil for a player with no stat block.
  def condition = document["condition"]

  # The world's numbers for the player, one line per half of the sheet it has.
  def sheet = document["sheet"]

  # THE SENTENCE THE NARRATOR IS TOLD THE STORY IS ASKING FOR, or nil for a
  # world with no arc and for one whose arc is walked to its end.
  def next_beat = document["next_beat"]

  # Story time now, for this game.
  def story_time = document["story_time"] && Time.zone.at(document["story_time"])

  def over? = document["over"]

  # WHY THE GAME STOPPED, in the words the play page and the refusal use, or nil
  # for a game still being played.
  def ended = document["ended"]

  def verbs = availability.verbs
  def verb(name) = availability.verb(name)
  def availability = @availability ||= Playthrough::Availability.new(playthrough, document)

  # What the play box completes after a slash; see `Playthrough::SlashMenu`.
  def slash_menu = @slash_menu ||= Playthrough::SlashMenu.new(playthrough, document)

  # THE SAME PANELS AS PLAIN LINES, for `rake game:mechanics`' `glance`. Names
  # only; ids and formatting beyond that are a front end's business.
  def to_s
    [
      "  room        #{room ? room.name : "nowhere"}#{" (in #{room.within})" if room&.within}",
      line("ways out", exits.map { |exit| "#{exit.name}#{" [unwritten]" unless exit.written}#{" [shut]" unless exit.open}" }, "none"),
      line("people", people.map { |person| [ person.name, person.condition, ("foe" if person.foe) ].compact.join(", ") }, "nobody else", "; "),
      line("things", things, "nothing fixed here", "; "),
      line("lying here", lying_here.map(&:name), "nothing"),
      line("carrying", carrying.map(&:name), "nothing"),
      line("condition", [ condition, *sheet ].compact, "no stat block", "; "),
      "  next beat   #{next_beat || "this world has no arc"}",
      *("  ended       #{ended}" if ended),
      *verbs.map { |verb| verb_line(verb) }
    ].join("\n")
  end

  private

  def fields(object) = object.transform_keys(&:to_sym)

  # THE THINGS PANEL AS ONE LINE: each fixture, marked when it is shut and
  # unsearched, with what lies on or in it after a colon.
  def things
    fixtures.map do |fixture|
      marked = fixture.state ? "#{fixture.name} (#{[ fixture.state, ("unsearched" unless fixture.searched) ].compact.join(", ")})" : fixture.name
      fixture.on.any? ? "#{marked}: #{fixture.on.join(", ")}" : marked
    end
  end

  def line(label, values, empty, separator = ", ")
    format("  %-11s %s", label, values.presence&.join(separator) || empty)
  end

  def verb_line(verb)
    return format("  %-11s blocked -- %s", verb.name, verb.reason) unless verb.available?

    aims = verb.aims && " at #{verb.aims.map(&:name).join(", ")}"
    format("  %-11s %s%s", verb.name, verb.targets.map(&:name).join(", "), aims)
  end
end
