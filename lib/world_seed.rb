# Seeded, playable worlds: the checked-in data files under db/seeds/worlds and
# the two halves of the tooling that keep them honest.
#
#   WorldSeed::Exporter  a generated Story -> a YAML file  (rake game:export)
#   WorldSeed::Loader    a YAML file -> database rows       (db/seeds.rb)
#
# Why this exists: generating a world costs minutes of live model calls and an
# API key, so a fresh clone had nothing to walk around in. A seeded world makes
# `bin/rails db:seed` produce something playable with no network at all.
#
# The files are AUTHORED ARTIFACTS. Export bootstraps one and rebuilds it after
# a schema change; from then on editing the YAML by hand is expected and
# supported. That is why the format is flat, ordered and commented rather than
# whatever was cheapest to emit -- see db/seeds/worlds/README.md.
module WorldSeed
  # Bumped when the file format changes in a way a loader cannot absorb. The
  # loader refuses a file it does not understand rather than half-loading it.
  #
  #   2  a world carries its own opening arrival: the required `opening_scene`
  #      key. A format 1 file has none, and a story without one opens on a room
  #      description standing in for an arrival nobody narrated.
  FORMAT = 2

  DIRECTORY = Rails.root.join("db/seeds/worlds")

  # The checked-in worlds, in a stable order so seeding is reproducible.
  def self.files
    Dir.glob(DIRECTORY.join("*.yml")).sort
  end

  # A filename for a story title: "The Drowned Ledger" -> "the-drowned-ledger".
  def self.slug(title)
    title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
  end

  # A leading article is not part of a name. Kept as a constant so the one
  # widening this makes over a plain downcase is visible in one place.
  LEADING_ARTICLE = /\A(?:the|a|an)\s+/

  # THE SAME THING UNDER A DIFFERENT WRITTEN NAME.
  #
  # A seed file's rows have no id -- the name IS the identity -- so a name that
  # is edited in the file is, to a loader matching on it, a row that does not
  # exist yet. `WorldSeed::Loader` then creates a second one and leaves the
  # first behind, which is how the captain's database came to hold both
  # "The Supply Closet" and "Supply Closet", with the office opening onto the
  # closet twice.
  #
  # So identity is asked one step wider than the written name: case, runs of
  # whitespace and a leading article are not part of it. Deliberately NOT wider
  # than that -- punctuation, possessives and plurals stay significant, because
  # every further step buys fewer real renames and risks folding two genuinely
  # different rooms into one, and a loader that merged two rooms would destroy
  # play rather than duplicate it. The two shapes actually observed are a case
  # change and a leading "The".
  #
  # Read by `WorldSeed::Loader` to recognize a renamed row and by
  # `Story::Doctor` to name a pair of rows that are one thing.
  def self.natural_key(name)
    name.to_s.downcase.gsub(/[[:space:]]+/, " ").strip.sub(LEADING_ARTICLE, "").strip
  end

  # THE ROW ONE OF A SEED FILE'S LOCATIONS IS, or nil for one this story has
  # never had -- and it is THE ONE READER for that question, deliberately. Three
  # callers ask it: `WorldSeed::Loader` decides whether to rename a row or write
  # a second one beside it, `Story::Doctor` decides whether somebody has left
  # the room the file puts them in, and `Story::Repair` puts them back. A loader
  # that recognized a row the doctor did not would report and then fail to
  # repair a defect that was never there.
  #
  # THREE PASSES, WIDENING, in the order of how certain each one is:
  #
  #   1. THE WRITTEN NAME, case-insensitively, matched exactly as
  #      `Location::Generator#find_location` matches it, so nothing about how
  #      the generator and the loader agree on a room turns on the rest of this.
  #
  #   2. `.natural_key` -- A RENAME THE FILE MADE. See it for how far it goes
  #      and why it goes no further.
  #
  #   3. THE PLACE AND THE BOX -- A RENAME THE ENGINE MADE, which is the pass
  #      this exists for. `Location::RoomName` writes a room's name when
  #      somebody first walks into it, so a file that declares
  #      `The Custom House room 1` as a stub of a laid-out place can come back
  #      to a row called `the counting room`: neither written-name pass matches
  #      it, and without this one the loader wrote a SECOND room at the same
  #      coordinates of the same place -- the row
  #      `Story::Doctor#duplicate_locations` exists to report and
  #      `Location::Interior`'s reachability guarantee assumes away -- while
  #      `Story::Repair#repair_seeded_whereabouts` raised on the name it could
  #      not find.
  #
  # A ROOM'S IDENTITY INSIDE A PLACE IS ITS BOX. The coordinates are the
  # engine's own, no model ever proposes one and nothing in the app moves a room
  # after it is laid out (`Location::Interior`), so they are what still says
  # "this room" once the name has moved. It is the same argument
  # `.natural_key`'s header makes about a leading article, made one step
  # further out: identity is asked as wide as the evidence supports and no
  # wider.
  #
  # PASS 3 NEEDS THE FILE'S OWN DECLARATION OF THE ROOM and answers nil without
  # one, which is why it is an argument rather than something read off the name:
  # only the document says which place a room is in and where in it, and only
  # for a room the file lays out -- a `parent` plus all five of
  # `Location::Box::COLUMNS`. Every flat world and every ordinary place is
  # answered by the first two passes and never reaches it.
  #
  # AND PASS 3 IS NOT THE WHOLE OF WHAT A PARTED NAME MEANS. Recognizing the row
  # settles WHICH row; it does not settle what the row is then called, and the
  # answer there is not always the file's -- see `.keeps_its_own_name?`.
  def self.find_location(story, name, declaration = nil)
    # `Location.where(story_id:)` and not `story.locations`, deliberately: a
    # bare association read LOADS AND CACHES it, and the loader calls this in
    # the middle of writing the very rows it would be caching. A caller that
    # read `story.locations` afterwards -- `EngineSweep::Invariants` does --
    # would get the loader's half-written snapshot instead of the records.
    rows = Location.where(story_id: story.id)
    exact = rows.where("LOWER(name) = ?", name.to_s.downcase).first
    return exact if exact

    key = natural_key(name)
    found = rows.pluck(:id, :name).detect { |(_, candidate)| natural_key(candidate) == key }
    return Location.find(found.first) if found

    find_placed_location(story, declaration)
  end

  # PASS 3, ON ITS OWN. The place is looked up through `.find_location` rather
  # than by name here, so a place the file has itself renamed is still found --
  # and it recurses no further than once, because a place is declared with no
  # `parent` of its own to widen on.
  #
  # AT MOST ONE ROW CAN MATCH and that is a guarantee on both sides rather than
  # a hope: `WorldSeed::Loader#validate_boxes_do_not_overlap!` refuses a file
  # that declares two rooms of one place in the same place at once, and
  # `Story::Doctor#overlapping_sibling_rooms` reports a database that holds two.
  # `order(:id)` so a database that holds one anyway is answered the same way
  # twice.
  def self.find_placed_location(story, declaration)
    return nil if declaration.nil? || declaration["parent"].blank?
    return nil unless Location::Box.shape(declaration) == :box

    place = find_location(story, declaration["parent"])
    return nil if place.nil?

    box = Location::Box.of(declaration)
    Location.where(story_id: story.id, parent_location_id: place.id).order(:id)
            .detect { |room| room.box == box && exactly_one_name_is_a_placeholder?(place, declaration["name"], room.name) }
  end

  # EXACTLY ONE OF THE TWO NAMES IS A NUMBER `Location::Interior` WROTE, and
  # that is what holds pass 3 to the rename it exists for instead of letting it
  # identify rooms by coordinates in general.
  #
  # THE WRONG ANSWER IT REFUSES, because it is a wrong answer and not an error.
  # A file edited to MOVE a room and to declare a NEW room in the box it vacated
  # gives two declarations that the database answers in the wrong order:
  # `WorldSeed::Loader#load_locations!` walks the file in order and saves each
  # row before the next lookup, so the NEW room misses both written-name passes,
  # finds the still-unmoved played row sitting at its coordinates, and takes it.
  # The played row then comes back under the new room's name carrying somebody's
  # scenes and doorways, and the room that really moved is created fresh and
  # empty beside it. Declaring the two the other way round gives the right
  # answer, which is exactly what makes it worth refusing: nothing about the
  # document says which order an author meant.
  #
  # BOTH DIRECTIONS ARE LEGITIMATE, which is why it is not a test of one side.
  # The file still carrying the number while the row is named is a room somebody
  # walked into (`Location::RoomName`); the file naming the room while the row
  # still carries the number is an author naming a room the engine had not got
  # to. Each is one rename of one room, and neither is a coincidence of
  # coordinates.
  #
  # EXACTLY ONE AND NOT AT LEAST ONE, WHICH IS THE WHOLE POINT -- do not
  # "simplify" this to an `||`. Two NUMBERED rooms of one place satisfy an `||`,
  # and they are the pair most likely to be moved around a hand-edited file:
  # `rake game:export` writes the engine's numbers straight out, so an author
  # who moves `<place> room 1` up a storey and declares `<place> room 3` in the
  # box it came out of has written two placeholder names, and an `||` let room
  # 3's declaration capture room 1's played row on coordinates alone. Two rooms
  # that both carry names a PERSON wrote were already refused; two that both
  # carry numbers have to be refused for the same reason, and nothing is lost by
  # it -- pass 1 matches a numbered room by its exact name before pass 3 is ever
  # consulted, which is both the right answer and an order-independent one.
  def self.exactly_one_name_is_a_placeholder?(place, declared, carried)
    Location::Interior.placeholder_name?(place, declared) ^
      Location::Interior.placeholder_name?(place, carried)
  end

  # WHETHER A ROW `.find_location` RECOGNIZED KEEPS THE NAME IT ALREADY HAS
  # rather than taking the file's. It is the ONE exception to *the file's
  # spelling wins*, and it is narrow on purpose.
  #
  # A PLACEHOLDER IS PROVISIONAL AND NOT AN ASSERTION. `Location::Interior`
  # numbers a building's rooms before anybody walks in, and `rake game:export`
  # writes those numbers straight into a file -- so a world file carrying
  # `The Custom House room 1` is not saying the room is called that. It is
  # carrying the number the engine wrote while the room was still unwritten, and
  # `.placeholder_name`'s own header is where that is declared provisional.
  #
  # WHAT WRITING THE NUMBER BACK WOULD COST, which is why this exists at all.
  # `Location::RoomName` names a room of a place the first time somebody walks
  # into it, and the same transaction flips the room to `realized`.
  # `Location::Generator#realize!` returns an already-realized room untouched,
  # so a re-seed that put the file's number back over that name would undo the
  # naming FOR GOOD: nothing would ever propose a name for that room again, and
  # the player would read *"You are in The Custom House room 1 of The Custom
  # House"* for the rest of the game. That is the precise defect
  # `Location::RoomName` was built to remove, reintroduced by the reader built
  # to protect the row.
  #
  # BOTH HALVES ARE REQUIRED. A file that has been given a real room name IS
  # asserting one and re-asserts it like everything else in the document; a row
  # still carrying a number has no name of its own to keep. So the row wins only
  # where the file offers a placeholder and the row offers something else.
  #
  # IT CANNOT FIRE ON A MATCH THE FIRST TWO PASSES MADE, which is why it needs no
  # argument saying which pass found the row. Both of those compare the two
  # names -- exactly, or on `.natural_key` -- and `.placeholder_name?` reads the
  # natural key too, so a file name that is a placeholder makes the row's name
  # one as well and the second half of the test is false. Only the box pass can
  # hand back a row whose name is unlike the file's at all.
  def self.keeps_its_own_name?(row, declaration)
    place = row.containing_place
    return false if place.nil? || declaration.nil?

    Location::Interior.placeholder_name?(place, declaration["name"]) &&
      !Location::Interior.placeholder_name?(place, row.name)
  end

  # THE CHECKED-IN FILE FOR ONE STORY, matched on title the way
  # `WorldSeed::Loader` matches everything else, or nil for a story that is not
  # one of them -- which is every generated world and every engine-sweep copy.
  #
  # Nil on a malformed file too: a caller reading the file for corroborating
  # evidence must not be the thing that raises on a broken one, which is
  # `WorldSeed::Loader`'s job to complain about. `Story::Doctor` and
  # `Item::LayerBackfill` both read it here rather than each opening the
  # path, so "is this one of ours" has one answer.
  def self.checked_in_document(title)
    path = DIRECTORY.join("#{slug(title)}.yml")
    File.exist?(path) ? parse(File.read(path)) : nil
  rescue StandardError
    nil
  end

  # Prose is stored as a literal block scalar (`|-`) rather than a folded or
  # quoted one: one paragraph is one physical line, so editing a sentence
  # produces a one-line diff instead of reflowing the whole field, and what you
  # type in an editor is exactly what gets stored. Psych falls back to a quoted
  # scalar on its own for the few strings a block scalar cannot hold.
  BLOCK_SCALAR_THRESHOLD = 60

  def self.dump(document)
    stream = Psych::Nodes::Stream.new
    doc = Psych::Nodes::Document.new
    doc.children << node(document)
    stream.children << doc
    stream.to_yaml
  end

  # Hand-edited files carry timestamps, so Date/Time are permitted; nothing
  # else is. Loading a seed file never instantiates an application object.
  def self.parse(yaml)
    YAML.safe_load(yaml, permitted_classes: [ Date, Time ], aliases: false)
  end

  def self.node(value)
    case value
    when Hash
      Psych::Nodes::Mapping.new.tap do |mapping|
        value.each do |key, child|
          mapping.children << node(key.to_s) << node(child)
        end
      end
    when Array
      # A short array of short scalars stays on one line -- `between` is a pair
      # of location names and reads as a pair.
      style = inline_array?(value) ? Psych::Nodes::Sequence::FLOW : Psych::Nodes::Sequence::BLOCK
      Psych::Nodes::Sequence.new(nil, nil, true, style).tap do |sequence|
        value.each { |child| sequence.children << node(child) }
      end
    when String
      scalar(value, style_for(value))
    when nil
      scalar("", Psych::Nodes::Scalar::ANY)
    else
      scalar(value.to_s, Psych::Nodes::Scalar::PLAIN)
    end
  end

  def self.style_for(value)
    return Psych::Nodes::Scalar::LITERAL if value.length > BLOCK_SCALAR_THRESHOLD || value.include?("\n")

    needs_quoting?(value) ? Psych::Nodes::Scalar::SINGLE_QUOTED : Psych::Nodes::Scalar::ANY
  end

  # Both implicit flags are set, which lets the emitter reach for quotes on its
  # own where the surrounding context demands them -- a name containing a comma
  # inside a flow sequence, say. Without that it emits a `!` tag instead.
  def self.scalar(value, style)
    Psych::Nodes::Scalar.new(value, nil, nil, true, true, style)
  end

  # Quote a short string only when leaving it bare would change what it means.
  # Asked of YAML itself rather than of a list of special cases: if the string
  # on its own does not parse back as that exact string, it needs quoting.
  # Compared by class as well as value, because ActiveSupport makes a Time
  # equal to a String that describes it -- an ISO timestamp is exactly the
  # case that has to come back quoted.
  def self.needs_quoting?(value)
    parsed = parse(value)
    !(parsed.is_a?(String) && parsed == value)
  rescue Psych::Exception
    true
  end

  def self.inline_array?(value)
    value.all? { |child| child.is_a?(String) && child.length <= BLOCK_SCALAR_THRESHOLD && !child.include?("\n") }
  end

  private_class_method :node, :inline_array?, :needs_quoting?, :style_for, :scalar, :find_placed_location,
                       :exactly_one_name_is_a_placeholder?
end
