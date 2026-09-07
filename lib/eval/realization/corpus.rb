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
#
# WHAT IT CANNOT CATCH is whether a case is worth measuring -- whether this
# stub, in this world, with these neighbours, puts the room builder anywhere
# near the failure a check is looking for. That is the hand-verification, and
# every case carries its `why`.
class Eval::Realization::Corpus
  class Invalid < StandardError; end

  # ONE CASE: one stub, about to be written, in one world wound back to the
  # moment before it was.
  #
  # `also_reaches`, `absent` and `unwritten` are DECLARED rather than derived,
  # and `Eval::Realization::Stage`'s header says why at length: none of them is
  # recoverable from the records, and an earlier draft that inferred them from
  # id order produced a world state that never existed.
  Case = Data.define(:id, :story, :room, :reached_from, :also_reaches, :absent, :unwritten, :danger,
                     :expects_new_ground, :expects_inside, :shape, :why) do
    def initialize(reached_from: nil, also_reaches: [], absent: [], unwritten: [], danger: nil,
                   expects_new_ground: nil, expects_inside: nil, shape: nil, why: nil, **rest)
      super
    end

    def opening_room? = reached_from.blank?
    def expects_new_ground? = expects_new_ground == true
    def held_out? = Eval::Realization.held_out?(story)
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

    Case.new(id: row["id"], story: row["story"], room: row["room"],
             reached_from: row["reached_from"], also_reaches: Array(row["also_reaches"]),
             absent: Array(row["absent"]),
             unwritten: Array(row["unwritten"]), danger: row["danger"],
             expects_new_ground: row["expects_new_ground"], expects_inside: row["expects_inside"],
             shape: row["shape"], why: row["why"])
  end

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
      unless [ true, false, nil ].include?(kase.expects_inside)
        found << "#{kase.id}: `expects_inside` is true, false or left out -- a case with no label is out " \
                 "of both inside checks' denominators, and anything else is a label nothing can read"
      end
      if kase.danger.present? && !Location::DANGERS.key?(kase.danger)
        found << "#{kase.id}: danger #{kase.danger.inspect} is not one of #{Location::DANGERS.keys.join(", ")}"
      end
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
