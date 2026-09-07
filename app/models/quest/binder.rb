# WHERE A NAME THE ARC WAS WAITING FOR BECOMES A ROW IT POINTS AT.
#
# THE RULE THIS FILE IS: **binding is a side effect of admission.** The arc says
# what the world must contain; the world's own writers decide when it does, and
# the moment one of them writes a row it calls here with it. There is no arc
# writer, no arc registry and no second path by which a `Location`, a
# `Character` or an `Item` can come into existence -- which is the whole of what
# keeps the arc from being a railroad. It states a destination; it never lays
# track.
#
# THE THREE CALLERS ARE THE THREE WRITERS THAT ALREADY EXIST:
#
#   a place    `Location::Generator#create_stub!` -- the one place a room is
#              born, whoever named it: a model naming an exit, a world
#              mechanic, or `Quest::Deadline`.
#   a person   `Character::Registry#admit!` -- the one thing that puts somebody
#              in a room.
#   a thing    `Item::Registry#admit!` -- the one thing that creates a template.
#
# EACH OF THEM CALLS `.bind!` WITH THE ROW IT JUST WROTE and is told nothing
# back that it has to act on. That direction matters: a registry that had to ASK
# the arc whether a name was wanted would be a registry the arc could refuse,
# and a refused admission is the arc gating the world.
#
# NAMED `Binder` AND NOT `Binding`, which is the one thing here that is about
# Ruby rather than about the game: `::Binding` is a core class, and a
# `Quest::Binding` would shadow it for every constant lookup inside the `Quest`
# namespace. A file that has to explain why `Binding` means something else here
# is a file worth renaming instead.
#
# ONE `find_by`-SHAPED READ PER ADMISSION, and it is bounded by the arc's own
# size: a story has a handful of steps, and only the UNBOUND ones are ever
# looked at. A world with no arc at all -- which is every world in the
# repository but one, and every world generated before this shipped -- pays one
# `exists?` and stops.
#
# THE NAME MATCH IS `WorldSeed.natural_key`'s, not a plain downcase, and that is
# deliberate: an arc written by a model says *"the Blackfang Warren"* about a
# room a later call names *"Blackfang Warren"*, and a leading article is not
# part of a name anywhere else in this app either.
#
# WHAT IT WILL NOT DO, said out loud because both are tempting:
#
#   IT WILL NOT REPOINT A BOUND STEP. `Quest::Step#bind!` returns a bound step
#   untouched, so a second room called the same thing does not move the arc.
#   The first row with the name is the one the world grew for it.
#
#   IT WILL NOT BIND ACROSS STORIES. Every read is scoped to the row's own
#   story, so two worlds that happen to want a prince cannot bind each other's.
module Quest::Binder
  # Binds every open step of `record`'s story that was waiting for its name.
  # Returns the steps it bound, which is almost always none.
  #
  # `at:` is STORY TIME and defaults to the story's own clock -- the moment in
  # the fiction the world grew the thing, which is what `bound_at` means. A
  # caller with a playthrough in hand may pass that game's own moment.
  def self.bind!(record, at: nil)
    return [] if record.nil?

    story = story_of(record)
    return [] if story.nil?

    steps = waiting_steps(story, record)
    return [] if steps.empty?

    at ||= story.clock
    steps.each { |step| step.bind!(record, at: at) }
  end

  # The steps of this story's open arcs that would take this row. Read as a
  # small relation and filtered in Ruby, because `Quest::Step#takes?` is where
  # the name rule and the kind rule both live and there is to be exactly one
  # statement of each.
  def self.waiting_steps(story, record)
    Quest::Step.unbound
               .where(quest: story.quests.open_arcs)
               .order(:quest_id, :position)
               .select { |step| step.takes?(record) }
  end

  # WHICH STORY A ROW BELONGS TO, asked of the three kinds and of nothing else.
  # An `Item` has no story of its own -- it is reachable through the person
  # holding it or the room it is lying in (`Item.in_story`'s note) -- so it is
  # the one that has to be asked in two directions.
  #
  # AND ONLY A TEMPLATE EVER BINDS AN ARC. A playthrough's own copy is one
  # game's progress; the arc is the world's, and binding it to an instance would
  # point every player's arc at one player's ward stamp. What a player is
  # CARRYING is how a `hold_item` beat is reached (`Playthrough::Arc`), which is
  # a different question asked of a different layer.
  def self.story_of(record)
    case record
    when Location, Character then record.story
    when Item then record.template? ? (record.location&.story || record.character&.story) : nil
    end
  end
end
