# THE CASES, AND THE THING THAT STOPS A CASE BEING A CLAIM.
#
# `test/fixtures/files/realization_corpus.yml` is stubs about to be written: a
# world, a room in it, the neighbour it was reached from, and the two lists that
# say what the rest of the world looked like at that moment. Every fact the
# model will be told is then read out of the records that world really holds --
# the universe, the preface, the places that already exist, the names already
# spoken for, how many people and things the registries will still admit -- so
# the prompt a case sends is `Location::Generator`'s and not this file's.
#
# WHY THE FACTS ARE NOT WRITTEN IN THE FILE, which is `Eval::Prompt::Corpus`'s
# argument and holds harder here: a realization prompt is four fifths world.
# A case that hand-wrote its universe and its known-places list would drift from
# the app the first time a line was added to either, and the drift would show up
# as a prompt change nobody made.
#
# WHAT THE VALIDATOR CATCHES, and it runs offline in `bin/rails test`:
#
#   * A world this bench has no file for, or one it does not play
#     (`Eval::Realization::STORIES`).
#   * A `room`, `reached_from`, `also_reaches`, `absent` or `unwritten` name the
#     world does not have -- the commonest way to write a case that measures
#     nothing, because the staging would raise and the case would be a hole in
#     the run.
#   * A `reached_from` or an `also_reaches` that is not actually connected to the
#     room, which would be claiming a way back -- or a neighbour this stub could
#     already reach -- that never existed. The second one is what stops a case
#     whose `why` describes a multi-exit stub from quietly staging a room with
#     one way out.
#   * A stub with no room left for a way out, which would skip the exits call
#     entirely (`Location::Generator#write_exits!`) and quietly halve the case.
#   * A missing `expects_new_ground`, because `no_new_ground` is only judgeable
#     where the case has declared whether this room is one the story points
#     into. A dead end that names only the way back is a CORRECT answer -- the
#     prompt asks for exactly that -- and scoring it as a defect would measure
#     the corpus.
#   * A missing `shape` or `why`. `shape` is what the board groups by; `why` is
#     what makes a case auditable.
#   * A `teaser` on a case whose room the world ALREADY has, which would be a
#     stub written twice and a teaser nothing reads.
#   * A `teaser` with no `danger`. `Location::Danger.for_a_new_room` is keyed on
#     the STORY'S ID, and a staged copy of a world is issued a new one on every
#     load -- so a typed stub that did not declare its danger would be born
#     quiet on one run and dangerous on the next, and every figure keyed on it
#     would move for no reason anybody could see.
#   * An `inside` or a `population` on a case that FINDS its room. Those two are
#     what a real exits call supplied about a place that did not exist yet; a
#     room the world already holds has them on its own row, and a case that
#     restated them would be hand-writing a world fact.
#   * An expectation naming a label the model is never offered, or a danger
#     floor that is not a rung of `Location::Parameters::LADDER` -- an
#     expectation that can never be earned reads on a board as the prompt
#     failing rather than as a typo.
#
# THE TWO KINDS OF CASE, AND THE ONE KEY THAT TELLS THEM APART.
#
#   A CASE THAT FINDS ITS ROOM is the original shape: a room in a checked-in
#   world file, wound back to the stub it was. Its identity is the world's.
#   A CASE THAT CARRIES ITS ROOM has a `teaser`, and `Eval::Realization::Stage`
#   CREATES the stub instead of finding one. That is the promotion path -- a
#   kind the captain typed in `Lab::Realization` and scored has no room in any
#   world file, so until a case could carry its own stub a scored kind could
#   never be re-run against a changed prompt.
#
# WHY THE STUB'S TWO FACTS MAY LIVE IN THE FILE WHEN THE UNIVERSE MAY NOT, which
# is the line this header draws above and the one a reader will think is being
# crossed: A NAME AND A TEASER ARE THE ROOM'S OWN FACTS AND NOT THE WORLD'S. The
# corpus already declares `danger` per case for exactly that reason. What stays
# forbidden is unchanged: the universe, the preface, the places that already
# exist and the names already spoken for are all still read out of the records
# the world really holds, so a promoted case sends `Location::Generator`'s prompt
# and not this file's.
#
# AND THE EXPECTATION IT CARRIES. A promoted case brings the captain's own
# `expects_*` block with it -- what he said the picks should come back as, off
# `Lab::Realization::PICKS`, each a subset of that pick's closed list and the
# danger one an ordinal floor. Every key obeys `expects_inside`'s rule: A KEY
# LEFT OUT IS *DON'T CARE* and takes the case out of that figure's numerator AND
# its denominator, because a rate a check did not earn is worse than no rate.
#
# NOTHING SCORES THE EXPECTATION YET, and that is stated here rather than left
# to be discovered: this slice ships the case that can carry one, the staging
# that can stand it up and the digest that folds it. The figure over it is the
# agreement half of the plan and is filed apart -- so a case may today declare
# an expectation for a pick its own shape can never be offered, and no validator
# here refuses that.
#
# WHAT IT CANNOT CATCH is whether a case is worth measuring -- whether this
# stub, in this world, with these neighbours, puts the room builder anywhere
# near the failure a check is looking for. That is the hand-verification, and
# every case carries its `why`.
class Eval::Realization::Corpus
  class Invalid < StandardError; end

  # THE PICKS AN EXPECTATION MAY BE DECLARED FOR, read off `Lab::Realization`
  # rather than listed again. That table is the closed lists the realization
  # schemas are built from (`Location::Parameters`, `Location::Population`), so
  # an expectation cannot allow a label the model was never offered and a pick
  # added to the game arrives here with no edit.
  #
  # THE DIRECTION OF THE DEPENDENCY IS DELIBERATE. A case carries a KIND's
  # expectation, so the file format depends on the lab's table and never the
  # reverse -- the lab reads no case, and `Lab::Realization`'s header keeps the
  # two words tellable apart.
  def self.picks = Lab::Realization.picks

  # THE KEY EACH PICK'S EXPECTATION IS DECLARED UNDER, and TWO OF THEM ARE NOT
  # `expects_<pick>` BECAUSE ONE NAME IS ALREADY TAKEN FOR A DIFFERENT CLAIM.
  #
  # `expects_inside` is this file's own hand label: HOW MANY of the places this
  # stub's exits call names should be a building, as one of
  # `Lab::Exits::QUANTIFIER_NAMES`. The lab's `inside` pick is the BAND the
  # model chose for each place it named -- a different question with a different
  # answer shape, and `Lab::Realization::Pick`'s header says in so many words
  # that the two must not be confused when a kind is promoted. So the two
  # per-exit picks are declared under `expects_exit_*`, which says whose pick it
  # is in the key.
  EXIT_PICK_KEYS = { "inside" => "expects_exit_inside",
                     "population" => "expects_exit_population" }.freeze

  def self.expectation_key(pick) = EXIT_PICK_KEYS.fetch(pick.name, "expects_#{pick.name}")

  # THE DANGER EXPECTATION IS AN ORDINAL FLOOR AND NOT A LIST, because *"uneasy
  # or worse"* is the thing he actually means and collapsing it to one value
  # would manufacture misses. Its rungs are `Location::Parameters::LADDER`,
  # quietest first, and the floor is expanded to the set of rungs at or above it
  # -- so one word in the file is read as the same kind of allowed set as every
  # other key and nothing downstream has to know it was written differently.
  DANGER_FLOOR_KEY = "expects_danger_at_least".freeze

  # THE PICKS DECLARED AS A LIST -- every one but the danger floor above.
  def self.list_picks = picks.reject { |pick| pick.name == "danger" }

  def self.danger_pick = pick("danger")

  def self.pick(name) = picks.find { |entry| entry.name == name.to_s }

  # THE RUNGS AT OR ABOVE A FLOOR, quietest first. Nil for no floor declared,
  # which is *don't care*.
  def self.danger_at_least(floor)
    return nil if floor.blank?

    rung = Location::Parameters::LADDER.index(floor)
    rung.nil? ? [] : Location::Parameters::LADDER[rung..]
  end

  # ONE CASE: one stub, about to be written, in one world wound back to the
  # moment before it was -- or, where the case carries a `teaser`, one stub
  # CREATED in a world that never had it.
  #
  # `also_reaches`, `absent` and `unwritten` are DECLARED rather than derived,
  # and `Eval::Realization::Stage`'s header says why at length: none of them is
  # recoverable from the records, and an earlier draft that inferred them from
  # id order produced a world state that never existed.
  #
  # `teaser`, `inside` and `population` ARE THE STUB'S OWN THREE FACTS and are
  # read only on a case that carries its room: the name and the teaser are what
  # the captain typed, and the `inside` band and the `population` word are what
  # a real exits call would have supplied about a place that did not exist yet.
  # They are exactly `Location::Generator.create_stub!`'s parameters, which is
  # the app's own one path for a room being born.
  #
  # `expects` IS A HASH FROM A PICK'S NAME TO THE LABELS HE ALLOWS, and
  # `expects_danger_at_least` is the one ordinal floor. Both are *don't care*
  # when absent, on `expects_inside`'s rule.
  Case = Data.define(:id, :story, :room, :teaser, :reached_from, :also_reaches, :absent, :unwritten,
                     :danger, :inside, :population, :expects_new_ground, :expects_inside,
                     :expects_danger_at_least, :expects, :shape, :why) do
    def initialize(teaser: nil, reached_from: nil, also_reaches: [], absent: [], unwritten: [],
                   danger: nil, inside: nil, population: nil, expects_new_ground: nil,
                   expects_inside: nil, expects_danger_at_least: nil, expects: {}, shape: nil,
                   why: nil, **rest)
      super
    end

    def opening_room? = reached_from.blank?
    def expects_new_ground? = expects_new_ground == true
    def held_out? = Eval::Realization.held_out?(story)

    # THE INSIDE LABEL AS THE ONE THING IT MEANS, and `expects_inside` above is
    # kept AS WRITTEN so the validator can quote a word it does not recognise.
    # Everything that MEASURES reads these two instead:
    # `Lab::Exits.quantifier_for` is the single reader of a label in this
    # repository and it takes the four quantifier names and the two booleans the
    # label used to be, so a case written before the widening is the same
    # measurement it always was. Nil is *don't care*, which takes the case out
    # of both inside checks' denominators.
    def inside_quantifier = Lab::Exits.quantifier_for(expects_inside)

    # THE NORMALISED NAME -- what the bench stores on a row and what
    # `Eval::Realization.digest` folds, so `false` and `none of them` are one
    # measurement written two ways rather than two cases.
    def expects_inside_quantifier = inside_quantifier&.name

    # WHETHER THIS CASE CARRIES ITS ROOM RATHER THAN FINDING ONE. The `teaser`
    # is the whole of the test, because it is the one fact a world file cannot
    # supply for a room it does not have -- `Eval::Realization::Stage` reads the
    # same predicate and there is no second answer to which kind of case this is.
    def typed? = teaser.present?

    # THE LABELS ALLOWED FOR ONE PICK, or nil for *don't care*. The danger pick
    # is expanded off its floor here, so every caller reads one shape.
    def expects_for(pick)
      name = pick.respond_to?(:name) ? pick.name : pick.to_s
      return Eval::Realization::Corpus.danger_at_least(expects_danger_at_least) if name == "danger"

      expects[name].presence
    end

    # THE PICKS THIS CASE SAID ANYTHING ABOUT, in `Lab::Realization::PICKS`'
    # order -- `Lab::Realization::Kind#declared`'s reading, one level up.
    def declared = Eval::Realization::Corpus.picks.select { |pick| expects_for(pick) }

    def expectation? = declared.any?

    # THE EXPECTATION AS ONE LINE, for `Eval::Realization.digest`. Every pick in
    # a fixed order with its allowed set, so a key added, removed or reordered
    # in the file moves the digest and a re-ordering of the labels within one key
    # does not measure anything new either way.
    def expectation_line
      Eval::Realization::Corpus.picks.map { |pick|
        "#{pick.name}=#{Array(expects_for(pick)).sort.join("|")}"
      }.join(" ")
    end

    def to_s = "#{story} / #{room}"
  end

  def self.load(path = Eval::Realization::CORPUS)
    document = YAML.safe_load(File.read(path))
    raise Invalid, "#{path}: expected a mapping with `cases`" unless document.is_a?(Hash)

    new(path: path, cases: Array(document["cases"]).map { |row| kase(row, path) })
  end

  def self.kase(row, path)
    missing = %w[id story room] - row.keys
    raise Invalid, "#{path}: case #{row.inspect} is missing #{missing.join(", ")}" if missing.any?

    Case.new(id: row["id"], story: row["story"], room: row["room"], teaser: row["teaser"],
             reached_from: row["reached_from"], also_reaches: Array(row["also_reaches"]),
             absent: Array(row["absent"]),
             unwritten: Array(row["unwritten"]), danger: row["danger"], inside: row["inside"],
             population: row["population"],
             expects_new_ground: row["expects_new_ground"], expects_inside: row["expects_inside"],
             expects_danger_at_least: row[DANGER_FLOOR_KEY], expects: expects(row),
             shape: row["shape"], why: row["why"])
  end

  # THE `expects_*` BLOCK, READ INTO ONE HASH. A single string is accepted as a
  # one-label list, because a person writing "flooded" means the set holding it
  # and a file that only took a YAML sequence would be a file that raised on the
  # obvious spelling.
  def self.expects(row)
    list_picks.to_h { |pick| [ pick.name, labels(row[expectation_key(pick)]) ] }
              .reject { |_name, labels| labels.empty? }
  end

  def self.labels(value) = Array(value).map { |label| label.to_s.strip }.compact_blank.uniq

  attr_reader :path, :cases

  def initialize(path:, cases:)
    @path = path
    @cases = cases
  end

  def size = cases.size

  def by_shape = cases.group_by(&:shape)

  def stories = cases.map(&:story).uniq

  # The cases that answer one question, and nothing else -- the seam both other
  # corpora give, used for the same thing: a targeted probe for a few cents
  # rather than the whole file.
  def subset(&block) = self.class.new(path: path, cases: cases.select(&block))

  def for_shape(shape) = subset { |kase| kase.shape.to_s == shape.to_s }

  def sample(size) = size.to_i.positive? ? self.class.new(path: path, cases: cases.first(size.to_i)) : self

  # THE VERIFICATION, run offline in the test suite. Returns the complaints
  # rather than raising them, so one failing test prints all of them at once.
  def problems
    found = structural_problems
    return found if found.any?

    cases.each do |kase|
      Eval::Realization::Stage.open([ kase ]) do |stages|
        found.concat(problems_for(kase, stages[kase.id]))
      end
    rescue Eval::Realization::Stage::Unstageable => error
      found << error.message
    end
    found
  end

  def validate!
    found = problems
    raise Invalid, "#{path}:\n  #{found.join("\n  ")}" if found.any?

    true
  end

  private

  # The checks that need no records: ids, worlds, and the keys a board reads.
  def structural_problems
    found = []

    cases.map(&:id).tally.select { |_id, count| count > 1 }.each_key do |id|
      found << "case id #{id.inspect} is used more than once"
    end

    cases.each do |kase|
      unless Eval::Realization::STORIES.include?(kase.story)
        found << "#{kase.id}: #{kase.story.inspect} is not a world this bench builds rooms in " \
                 "(#{Eval::Realization::STORIES.join(", ")})"
        next
      end
      if Eval::Realization.world_file(kase.story).nil?
        found << "#{kase.id}: there is no world file for #{kase.story.inspect} under " \
                 "#{Eval::Realization::WORLD_ROOTS.join(" or ")}"
      end
      found << "#{kase.id}: a case needs a `shape`, which is what the board groups by" if kase.shape.blank?
      found << "#{kase.id}: a case needs a `why`, which is what makes it auditable" if kase.why.blank?
      unless [ true, false ].include?(kase.expects_new_ground)
        found << "#{kase.id}: a case needs `expects_new_ground: true|false` -- a dead end that names " \
                 "only the way back is a correct answer, and `no_new_ground` is unjudgeable without it"
      end
      if !kase.expects_inside.nil? && kase.inside_quantifier.nil?
        found << "#{kase.id}: `expects_inside` is one of #{Lab::Exits::QUANTIFIER_NAMES.join(", ")} " \
                 "-- or left out, which takes the case out of both inside checks' denominators. " \
                 "#{kase.expects_inside.inspect} is a label nothing can read. (`true` and `false` are " \
                 "still read, as the older spellings of " \
                 "#{Lab::Exits::FROM_BOOLEAN.values.map(&:inspect).join(" and ")}.)"
      end
      if kase.danger.present? && !Location::DANGERS.key?(kase.danger)
        found << "#{kase.id}: danger #{kase.danger.inspect} is not one of #{Location::DANGERS.keys.join(", ")}"
      end
      found.concat(stub_problems(kase))
      found.concat(expectation_problems(kase))
    end

    found
  end

  # THE THREE FACTS A CASE MAY CARRY ABOUT ITS OWN STUB, and the rules are all
  # about which KIND of case may carry them.
  #
  # A `danger` IS REQUIRED ON A TYPED CASE and this is the check with the sharpest
  # reason behind it. `Location::Generator.create_stub!` rolls the danger through
  # `Location::Danger.for_a_new_room`, which is keyed on the STORY'S ID -- and a
  # staged copy of a world is issued a new id on every load. So a typed stub that
  # left its danger to the roll would be born quiet on one run and dangerous on
  # the next: the room's danger is stated in the detail prompt, so
  # `Eval::Realization::Version.offline` would report a different prompt digest
  # each time it was asked and the bench would call a tree unbaselined for no
  # reason anybody could see. A case that FINDS its room has the world's own
  # danger to fall back on and needs no such key.
  def stub_problems(kase)
    found = []

    if kase.typed?
      if kase.danger.blank?
        found << "#{kase.id}: a case that carries its own stub needs a `danger` -- the roll a new room " \
                 "would get is keyed on the story's id, which a staged copy is issued afresh on every " \
                 "load, so an undeclared danger would move the prompt digest between two runs of one tree"
      end
    else
      %w[inside population].each do |key|
        next if kase.public_send(key).blank?

        found << "#{kase.id}: `#{key}` is a fact a real exits call supplied about a place that did not " \
                 "exist yet, so it belongs only to a case that carries its own stub (`teaser`). The room " \
                 "this case finds has it on its own row."
      end
    end

    if kase.inside.present? && !Location::Parameters::INSIDE.key?(kase.inside)
      found << "#{kase.id}: inside #{kase.inside.inspect} is not one of " \
               "#{Location::Parameters::INSIDE.keys.join(", ")}"
    end
    if kase.population.present? && !Location::Population::LABELS.include?(kase.population)
      found << "#{kase.id}: population #{kase.population.inspect} is not one of " \
               "#{Location::Population::LABELS.join(", ")}"
    end

    found
  end

  # AN EXPECTATION MAY ONLY NAME A LABEL THE MODEL IS OFFERED, which is
  # `Lab::Realization::Kind#expectations_are_labels_the_model_is_offered`'s rule
  # one level up and it is the same rule for the same reason: the model cannot
  # answer a word its schema's enum does not carry, so a set holding anything
  # else is a rate that can never be earned and reads on a board as the prompt
  # failing rather than as a typo.
  def expectation_problems(kase)
    found = []

    self.class.list_picks.each do |pick|
      stray = Array(kase.expects[pick.name]) - pick.values
      next if stray.empty?

      found << "#{kase.id}: `#{self.class.expectation_key(pick)}` names #{stray.map(&:inspect).join(", ")}, " \
               "which is not on the list the model picks from (#{pick.values.join(", ")})"
    end

    floor = kase.expects_danger_at_least
    if floor.present? && !Location::Parameters::LADDER.include?(floor)
      found << "#{kase.id}: `#{DANGER_FLOOR_KEY}` is a rung of the ladder and #{floor.inspect} is not one " \
               "(#{Location::Parameters::LADDER.join(", ")})"
    end

    found
  end

  # The checks that need the world stood up.
  #
  # AN INTERIOR ROOM IS THE ONE CASE THAT MEASURES ONE CALL ON PURPOSE. Its ways
  # out are the engine's -- decided by `Location::Interior` before anybody typed
  # a line -- so `Location::Generator#write_exits!` asks for none, and the exit
  # allowance says nothing about whether the case is worth measuring. What it
  # measures instead is the detail call handed a floor plan
  # (`Location::Plan`), which is a prompt shape no other case in this corpus can
  # reach. It is recognised the way the generator recognises it, both halves.
  # AND A PLACE IS THE SECOND CASE THAT MEASURES ONE CALL ON PURPOSE, for the
  # mirror image of the interior room's reason: a building's ways out are its
  # ROOMS' ways out by the time it has been laid out, so
  # `Location::Generator#write_exits!` asks for none of them either
  # (`#open_the_way_in!` has just moved every doorway it had). What such a case
  # measures instead is the `parameters` block -- the picks a model makes about
  # a building, which no other case in this corpus can be offered at all.
  def problems_for(kase, standing)
    return [ "#{kase.id}: could not be staged" ] if standing.nil?
    return [] if standing.plan
    return [] if standing.place?
    return [] if standing.exit_allowance.positive?

    [ "#{kase.id}: #{kase.room.inspect} has no room left for a way out, so write_exits! would make no " \
      "call at all and the case would measure half a realization" ]
  end
end
