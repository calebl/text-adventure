# THE ROOM A CORPUS LINE WAS LABELLED AGAINST, REBUILT FROM THE SEED FILE.
#
# A classifier label is only meaningful next to the closed sets the model was
# offered: "take the apron" resolves to a record in the supply closet and to
# nothing in the office, and a corpus that stored the line without the room
# would be measuring the wrong thing half the time. So a corpus line names a
# POSITION, and a position is a seeded world plus a room plus a list of typed
# setup lines -- and this class is what turns that back into a `Playthrough`
# standing somewhere with things in its hands.
#
# THE THREE GUARANTEES ARE `EngineSweep::Walk`'S, for the same reasons:
#
#   1. ITS OWN COPY OF THE WORLD. The seed file is loaded under a title of this
#      class's own, so a bench run cannot read, move or delete anything in the
#      world somebody has been playing -- and the whole run is inside a
#      transaction that is rolled back, so it leaves the database as it found
#      it. Run it against a half-played development database and both survive.
#   2. THE SETUP MAKES NO MODEL CALL. Setup lines are walked through
#      `Playthrough::Mechanics` with `model: false` -- the fixed grammar and the
#      real `#carry!` / `#put_down!` / `#stand_in!` -- so getting into position
#      costs nothing and is deterministic to the row. The ONLY model call a
#      bench run makes is the one being measured.
#   3. THE WORLD DOES NOT MOVE UNDERNEATH IT. `WorldMechanic` runs on
#      `MAX(scenes.story_timestamp)`, no-model mode writes no Scene, and the
#      bench writes none either -- so a position is the same position on the
#      hundredth line as on the first.
#
# WHY THE SETUP IS TYPED LINES AND NOT ATTRIBUTES. A position built by writing
# `items.playthrough_id` directly would be a position the engine cannot reach,
# and a corpus of those would measure the classifier against states no player
# can be in. `go to the Supply Closet` / `take the private index` is a state
# somebody walked into.
class Eval::Classifier::Stage
  # ONE COPY OF THE WORLD PER POSITION, and the position's id is in the title
  # because that is what makes them separate copies. `WorldSeed::Loader` is
  # idempotent on the story TITLE, so two positions cut from one seed file under
  # one title are two playthroughs of ONE world -- and the closed-set readers are
  # live queries, so a position whose setup put the tide-slate on the floor would
  # be putting it on the floor of every other position in that world. Ten seed
  # loads is the price of ten independent starting states, paid once per bench
  # run and offline.
  def self.title_for(position) = "#{position.story} (classifier bench: #{position.id})"

  class Unstageable < StandardError; end

  # A position, staged, with the closed sets it offers read back off the
  # records. `offered` is what the model will be shown; the corpus validator
  # compares every label against it, which is what makes a label auditable
  # rather than a claim.
  Standing = Data.define(:position, :playthrough, :classifier) do
    def location = playthrough.current_location
    def exits = classifier.exits_here
    def cast = classifier.characters_here
    def here = classifier.items_here
    def carried = classifier.items_carried

    # EVERY NAME THE ENUM WILL HOLD, which is the union `Playthrough::Classifier#classify`
    # builds -- exits, both names of everybody here, what is lying here and what
    # is carried.
    def offered
      exits.map(&:name) + cast.flat_map { |person| [ person.fullname, person.nickname ] } +
        here.map(&:name) + carried.map(&:name)
    end

    # THE SET ONE ACTION READS AGAINST, asked of the classifier rather than
    # rebuilt, so a label cannot be validated against a list the action does not
    # actually use.
    def offered_for(action) = classifier.offered_for(action)

    def to_s
      format("%s / %s -- out: [%s] here: [%s] carrying: [%s] present: [%s]",
             position.story, location&.name,
             exits.map(&:name).join(", "), here.map(&:name).join(", "),
             carried.map(&:name).join(", "), cast.map(&:fullname).join(", "))
    end
  end

  # Stages every position the corpus names and yields them all at once, inside
  # ONE rolled-back transaction. All at once because a position is expensive to
  # build (a seed load) and free to hold, and because the alternative -- staging
  # per line -- would reload a world three hundred times.
  # RETURNS WHAT THE BLOCK RETURNED, and it has to be captured on the way out
  # rather than taken from the transaction: `ActiveRecord::Base.transaction`
  # answers nil when `ActiveRecord::Rollback` is raised inside it, so a caller
  # reading the return value would get nothing at all.
  #
  # THE ROLLBACK IS THE LAST STATEMENT OF THE BLOCK AND NOT AN `ensure`, which
  # is `EngineSweep::Walk`'s shape and matters for the same reason: an `ensure`
  # that raises `ActiveRecord::Rollback` REPLACES an exception already in
  # flight, so a bench that failed inside the block would come back as a silent
  # nil instead of an error. A real exception still rolls the transaction back
  # on its own way out.
  def self.open(positions)
    answer = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      stages = positions.to_h { |position| [ position.id, new(position).stand! ] }
      answer = yield stages
      raise ActiveRecord::Rollback
    end

    answer
  end

  attr_reader :position

  def initialize(position)
    @position = position
  end

  def stand!
    story = load_world!
    place_the_cast!(story)
    playthrough = new_playthrough(story)
    mechanics = Playthrough::Mechanics.new(playthrough, model: false)

    position.setup.each do |typed|
      report = mechanics.run(typed)
      next unless report.refused?

      raise Unstageable, "#{position.id}: setup line #{typed.inspect} was refused offline -- #{report.refusal}"
    end

    playthrough.reload
    move_to_room!(playthrough, story)

    Standing.new(position: position, playthrough: playthrough,
                 classifier: Playthrough::Classifier.new(playthrough))
  end

  private

  # WHERE THE RECORDS PUT PEOPLE, when a position needs them somewhere the seed
  # file does not. Through `Character#move_to!` -- the explicit writer -- and
  # before the playthrough exists, so the party's derived position cannot be
  # confused with it. See `Eval::Classifier::Corpus::Position`.
  def place_the_cast!(story)
    position.cast.each do |fullname, room_name|
      person = story.characters.find_by(fullname: fullname)
      raise Unstageable, "#{position.id}: #{story.title.inspect} has nobody called #{fullname.inspect}" if person.nil?

      room = room_name && story.locations.find_by(name: room_name)
      if room_name && room.nil?
        raise Unstageable, "#{position.id}: #{story.title.inspect} has no room called #{room_name.inspect}"
      end

      person.move_to!(room)
    end
  end

  # THE ROOM IS STATED AND THE SETUP IS OPTIONAL, and the room wins: a position
  # says where the player stands, so a setup that walked somewhere else is a
  # setup line, not the position. Standing is `Playthrough::Turn#stand_in!`'s
  # column and nothing else -- no Scene, so no clock and no visit stamp.
  def move_to_room!(playthrough, story)
    room = story.locations.find_by(name: position.room)
    raise Unstageable, "#{position.id}: #{story.title.inspect} has no room called #{position.room.inspect}" if room.nil?

    playthrough.update!(current_location: room)
  end

  def load_world!
    file = Rails.root.join("db/seeds/worlds", "#{WorldSeed.slug(position.story)}.yml")
    raise Unstageable, "#{position.id}: there is no seeded world #{position.story.inspect} (#{file})" unless File.exist?(file)

    document = WorldSeed.parse(File.read(file))
    document["story"]["title"] = self.class.title_for(position)
    WorldSeed::Loader.new(document, source: file.to_s).load!
  end

  # Where a player starts, the same two the browser hands a new playthrough --
  # see `PlaythroughsController#create` and `EngineSweep::Walk#playthrough_for`.
  # The starting inventory is taken up here rather than assumed, because what
  # the party carries is the playthrough's copy and not the protagonist's row.
  def new_playthrough(story)
    opening = story.locations.realized.order(:id).first
    raise Unstageable, "#{position.id}: #{story.title.inspect} has no realized room to stand in" if opening.nil?

    Playthrough.create!(story: story, character: story.protagonist,
                        current_location: opening, current_scene: story.opening_scene)
  end
end
