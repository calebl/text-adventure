# THE CORPUS, REALIZED THROUGH THE REAL GENERATOR, TWO CALLS A CASE.
#
# `Location::Generator#realize!` runs whole, on a staged stub, with NOTHING
# replaced. That is the difference between this and the other two benches and it
# is worth stating plainly: the prompt bench has to stand in for the classifier
# (a second model between the case and the passage would make a case take a
# branch its facts were not written for), and the classifier bench asks one call
# in isolation. A realization has no such seam and needs none -- the two calls
# ARE the thing being measured, in the order and the conversation the app makes
# them in, so the app is simply run.
#
# WHAT IS READ AFTERWARDS IS THE APP'S OWN ACCOUNT OF THE CALL. The prompts, the
# instruction block, the raw JSON that came back, the tokens: all of it off the
# `chats` and `messages` rows `BaseAgent` wrote, exactly as
# `Playthrough::Feedback#provenance_for` and `Eval::Prompt::Bench#receipts_for`
# read them. Nothing here rebuilds a prompt to record it, because a rebuilt
# prompt is a prompt nobody sent.
#
# AND WHAT THE REGISTRIES DID WITH THE ANSWER, off the records: who is standing
# in the room, what is lying in it, and which places came into existence. That
# is the half no reading of the answer could give -- `Item::Registry` and
# `Character::Registry` refuse a proposal for reasons the model was told about
# and reasons it was not, and the difference between what was named and what was
# admitted is a defect with a cost.
#
# ITS OWN COPY OF THE WORLD PER CASE AND PER REPETITION, through
# `Eval::Realization::Stage`. A realization writes rows -- a room, its floor,
# its cast, its neighbours -- so a second repetition standing on the first one's
# world would be realizing a room into a world that already held the answer. The
# stage rolls the whole thing back when the receipts have been read out into
# Ruby.
#
# SEVERAL REPETITIONS, BECAUSE ONE IS NOT A MEASUREMENT. The default is
# `Eval::Noise::MIN_RUNS`, so a run taken at the default is a run a later
# comparison can give a verdict against.
#
# PER MODEL, ONE MODEL PER ARM, NOTHING BEHIND IT -- `Eval::Classifier::Arm`,
# shared rather than copied. Read its header for the three reasons a measurement
# wants the rotation off.
#
# SERIAL, ON PURPOSE, and for a stronger reason than the prompt bench's: this
# one stages a copy of a world PER CASE and then writes into it. Two cases in
# flight are two stagings in flight against one SQLite connection, and the
# isolation each case needs is exactly what makes them impossible to share. The
# latencies below are therefore serial figures -- what one player waits for a
# room, with nothing queued behind it.
#
# AND THE FIRST CALL IS ITS OWN FIGURE. Every arm gets one warm realization
# before its first pass, timed, reported as `first call` and excluded from the
# latencies -- so the figures the board prints are WARM-CACHE FIGURES and say so.
class Eval::Realization::Bench
  # WHAT ONE CASE CAME BACK AS, with the facts it was asked against.
  #
  # `facts` is the world as the RECORDS held it BEFORE the call -- the
  # allowances, the rolled cast slots, the places that already exist and which
  # of them are written, the names already spoken for. It is stored beside the
  # answer so `Eval::Realization::Scorer` can be run again, offline and for
  # nothing, without the calls being paid for a second time.
  #
  # `answers` is the provider's own JSON for each of the two calls, by name, and
  # `after` is what the registries made of it.
  Reading = Data.define(:kase, :arm, :rep, :facts, :answers, :after, :seconds,
                        :input_tokens, :output_tokens, :calls, :answered_by,
                        :instructions, :prompts, :missing_fields, :cap_hits, :error) do
    def id = kase.id
    def shape = kase.shape
    def story = kase.story
    def failed? = !error.nil?
    def held_out? = Eval::Realization.held_out?(story)

    # WHY A CALL FAILED, WHAT IT COST IN EXTRA CALLS AND WHETHER IT WAS A
    # REFUSAL ARE NOT ASKED HERE. They are read off the stored ROW by
    # `Eval::Realization::Scorer::Reading`, which is the object that survives
    # being written to a file -- so a set rescored offline and a live pass
    # cannot disagree about what a refusal is. A second spelling on this class
    # would be a second answer nobody reads.

    # THE GUARD, not a figure: with an arm of one there is nothing to rotate to,
    # so this is false on every reading of a healthy run.
    def rotated?
      return false if answered_by.nil?

      answered_by != Eval::Classifier::Arm.parse(arm).model
    end

    # AND THE ARM IS ON THE ROW AS WELL AS ON THE PASS, which looks like
    # duplication and is the thing that makes the guard above survive being
    # written to a file. `Eval::Realization::Result.rotated?` is asked about a
    # ROW -- by `figures_of`, which is the one place a figure is computed, and
    # by every reader of a set loaded off disk -- and it has to short-circuit
    # false on a row that does not say which arm it belongs to, or a set with no
    # arms anywhere would report every reading rotated. An arm carried only
    # beside the rows is therefore an arm the row cannot be judged against, and
    # `rotations` would read zero on a run where the pinning really failed:
    # silence, in the one figure whose whole job is to say the column is not the
    # model it is labelled with. `rep` goes with it for the same reason -- a row
    # lifted out of its pass has to say which repetition it was.
    #
    # THE SAME SHAPE MAY EXIST IN THE OTHER TWO BENCHES. They are other
    # instruments' measurement files and are not this task's to edit; this note
    # is here so whoever looks knows what to look for.
    def stored_arm = { arm: arm, rep: rep }

    def to_h
      { id:, shape:, story:, held_out: held_out?, room: kase.room,
        **stored_arm, facts:, answers:, after:,
        seconds: seconds&.round(4), input_tokens:, output_tokens:, calls:,
        answered_by:, instructions_digest: Playthrough::PromptVersion.of(instructions),
        prompts:, missing_fields:, cap_hits:, error: }
    end
  end

  # WHAT THE FIRST CALL COST, once per arm. Reused from the classifier bench
  # rather than redefined: it is the same fact about the same thing.
  Warmup = Eval::Classifier::Bench::Warmup

  # ONE PASS OF THE WHOLE CORPUS ON ONE MODEL. Every figure it answers is
  # computed from the READINGS and their stored facts, which is what lets a set
  # loaded off disk answer the same questions. STRING KEYS THROUGHOUT, because
  # this hash is written to a file and read back by
  # `Eval::Realization::Result::Stored`, and one shape has to serve both.
  Pass = Data.define(:arm, :rep, :readings) do
    def rows = readings.map { |reading| reading.to_h.transform_keys(&:to_s) }

    def to_h
      { "arm" => arm, "rep" => rep }.merge(Eval::Realization::Result.figures_of(rows))
                                    .merge("readings" => rows)
    end

    # THE FORM EVERYTHING DOWNSTREAM READS. A live pass and a pass loaded off
    # disk are the same object from here on, which is what stops a figure being
    # computed two ways.
    def stored = Eval::Realization::Result::Stored.new(to_h)
  end

  # THE SCHEMA EACH CALL SENDS, by name. A map rather than a lookup on the
  # agent, because the agent is gone by the time a stored set is rescored and
  # the call's name is what a row records.
  SCHEMAS = { "detail" => Location::DetailSchema, "exits" => Location::ExitsSchema }.freeze

  attr_reader :corpus, :arms, :reps, :io

  def initialize(corpus: Eval::Realization.corpus, arms: nil, reps: Eval::Noise::MIN_RUNS, io: $stdout)
    @corpus = corpus
    @arms = Eval::Classifier::Arm.all(arms.presence || [ BaseAgent::REMOTE_MODEL_IDS.first ])
    @reps = reps
    @io = io
  end

  # Returns an `Eval::Realization::Result`. A case whose call fails is recorded
  # as a failure and the pass keeps going: a provider dropping one call in a
  # hundred must not cost the whole run.
  def run
    passes = []
    warmups = []

    arms.each do |arm|
      arm.pinned do
        warmups << warm(arm)
        (1..reps).each { |rep| passes << play(arm, rep) }
      end
    end

    Eval::Realization::Result.new(
      corpus_size: corpus.size, corpus_digest: Eval::Realization.digest(corpus),
      arms: arms.map(&:id), reps: reps, passes: passes.map(&:stored), warmups: warmups,
      **Eval::Realization::Version.of(passes)
    )
  end

  private

  # ONE REALIZATION BEFORE THE MEASUREMENT, TIMED AND THEN SET ASIDE. A real
  # case on a real world, because a warm-up that took a different path would
  # warm a different thing. Its duration is the cold start made visible as its
  # own number rather than hidden in the band.
  def warm(arm)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    reading = read(corpus.cases.first, arm, 0)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    warmup = Warmup.new(arm: arm.id, seconds: seconds, residency: arm.keep_resident!, error: reading.error)
    io&.puts format("  %-32s first call %.1fs (excluded from the figures below)%s",
                    arm.id, seconds, reading.error ? " -- FAILED: #{reading.error}" : "")
    warmup
  end

  def play(arm, rep)
    io&.print format("  %-32s rep %d ", arm.id, rep)
    readings = corpus.cases.map { |kase| read(kase, arm, rep) }

    pass = Pass.new(arm: arm.id, rep: rep, readings: readings)
    scored = Eval::Realization::Scorer.new(pass.rows)
    io&.puts format("%3d rooms, %2d flagged, %.1fs median%s%s",
                    scored.scanned, scored.flags.size,
                    Eval.median(readings.filter_map(&:seconds)),
                    readings.count(&:failed?).positive? ? ", #{readings.count(&:failed?)} FAILED" : "",
                    readings.any?(&:rotated?) ? ", ROTATED -- THE PINNING FAILED" : "")
    pass
  end

  # ONE CASE, IN ITS OWN COPY OF ITS WORLD. Everything worth keeping is read out
  # into Ruby before the stage rolls the copy back, because after that there is
  # nothing left to read.
  def read(kase, arm, rep)
    Eval::Realization::Stage.open([ kase ]) { |stages| build(kase, stages.fetch(kase.id), arm, rep) }
  end

  # THE FACTS FIRST, THEN THE CALL. The order matters: `#facts_before` asks the
  # cast registry for its slots, which ROLLS the race, age and sex of everybody
  # this call may name and memoizes them -- the same memo
  # `Location::Generator#people_instructions` reads when it builds the prompt a
  # moment later. Reading them afterwards would be reading them; reading them
  # first is what guarantees the prompt and the stored facts describe one set of
  # people.
  def build(kase, standing, arm, rep)
    facts = facts_before(kase, standing)
    before = standing.story.locations.pluck(:name)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = nil
    begin
      standing.generator.realize!
    rescue StandardError => e
      error = "#{e.class}: #{e.message}"
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    receipts = receipts_for(standing.generator)

    Reading.new(
      kase: kase, arm: arm.id, rep: rep, facts: facts,
      answers: receipts[:answers], after: after(standing, before),
      # A FAILED CALL HAS NO LATENCY, deliberately: how long it took to fail is
      # a fact about the failure and not about how fast this model answers.
      seconds: (elapsed if error.nil?),
      input_tokens: receipts[:input_tokens], output_tokens: receipts[:output_tokens],
      calls: receipts[:calls], answered_by: receipts[:answered_by],
      instructions: receipts[:instructions], prompts: receipts[:prompts],
      missing_fields: receipts[:missing_fields], cap_hits: receipts[:cap_hits], error: error
    )
  end

  # THE WORLD AS THE RECORDS HELD IT BEFORE THE CALL, and every list is asked of
  # the STANDING rather than rebuilt here -- `Eval::Realization::Stage::Standing`
  # reads them off the same registries and the same scopes the prompt does, so a
  # checker cannot be scoring against a list the prompt never carried.
  def facts_before(kase, standing)
    { "room" => standing.location.name,
      "teaser" => standing.location.teaser,
      "danger" => standing.location.danger,
      "danger_share" => standing.location.danger_share,
      "expects_new_ground" => kase.expects_new_ground?,
      # THE HAND LABEL, AS THE CASE WROTE IT -- true, false or nil, and nil is
      # the ordinary answer. It is the one thing in this bench that is not a
      # record on both sides, because there is no record of what a world SHOULD
      # have been; `Eval::Realization::Corpus`'s header says which cases carry
      # one and why most do not.
      "expects_inside" => kase.expects_inside,
      # THE WAY BACK, BY NAME. `reachable` is every neighbour the stub already
      # had, which on a multi-exit stub is not the same thing -- and the exits
      # prompt's dead-end sentence is about the place the player CAME FROM
      # specifically. `Eval::Realization::Scorer#correct_dead_end?` cannot tell
      # the two apart without this. Nil on an opening room, which has no way
      # back at all.
      "reached_from" => kase.reached_from,
      # THE FLOOR PLAN THE DETAIL PROMPT STATED, for a room inside a laid-out
      # place and nil for every other room. It is what the two geometry checks
      # read a description against, and it is stored rather than re-derived at
      # scoring time for this file's usual reason: the world is rolled back when
      # the pass ends, so a checker that wanted to ask the records would have
      # nothing to ask.
      "plan" => standing.plan,
      # WHETHER THIS ROOM WAS OFFERED THE PARAMETERS BLOCK -- true for a
      # building with no inside yet and false for every other room in the game.
      # The GATE the parameters checks put their denominator behind, and a set
      # stored before the block existed has no key and reads false, which takes
      # those rows out entirely: `Scorer::Reading#records_the_way_back?`'s rule,
      # and its reason -- a rate a check never earned is worse than no rate.
      "parameters_asked" => standing.place?,
      # WHETHER THIS ROOM WAS ASKED TO NAME ITSELF, and the names the prompt
      # showed it as spoken for. The GATE both name checks put their
      # denominator behind: a set stored before this key existed reads false and
      # is out of them entirely, which is `Scorer::Reading#records_the_way_back?`'s
      # rule -- a rate a check never earned is worse than no rate.
      "name_asked" => standing.name_asked?,
      "name_taken" => standing.name_taken,
      "people_allowance" => standing.people_allowance,
      "item_allowance" => standing.item_allowance,
      "exit_allowance" => standing.exit_allowance,
      "slots" => standing.slots,
      "places" => standing.places,
      "reachable" => standing.reachable,
      "taken_names" => standing.taken_names,
      "all_names" => standing.all_names,
      "present" => Character.present_in(standing.location).pluck(:fullname),
      "monstrous_races" => standing.story.universe.monstrous_races.pluck(:name) }
  end

  # WHAT THE REGISTRIES MADE OF THE ANSWER. The half no reading of the JSON
  # could give: a name refused, a cap reached, a person already standing
  # somewhere else. Read off the records the way the game reads them.
  def after(standing, before)
    room = standing.location.reload
    # WHAT THE ROOM IS CALLED AFTERWARDS, which is the only way to see what
    # `Location::RoomName` did with the proposal: it refuses on five separate
    # grounds and the room simply keeps its placeholder, so re-deriving the
    # decision in the scorer would be a second implementation of the one thing
    # that owns it. `Scorer#judge_room_name_refused` reads this against
    # `facts["room"]` and nothing else.
    { "name" => room.name,
      # THE BUILDING THE PICKS PRODUCED, or an empty list for every room that is
      # not one. It is the only record of what the parameters did: none of them
      # has a column, so the rooms the layout wrote ARE the answer
      # (`Eval::Realization::Stage::Standing#rooms_laid_out`).
      "rooms" => standing.rooms_laid_out,
      "people" => Character.present_in(room).pluck(:fullname),
      "items" => room.items.pluck(:name),
      "exits" => room.exits.order(:id).pluck(:name),
      "new_places" => standing.story.locations.pluck(:name) - before }
  rescue ActiveRecord::RecordNotFound
    # The room itself did not survive the call. Nothing in `Location::Generator`
    # destroys it, so this is unreachable in a healthy run and is here so a run
    # that hit it reports a case rather than dying in the middle of a pass.
    {}
  end

  # WHAT THE TWO CALLS COST AND WHAT THEY WERE TOLD, off the conversation the
  # generator left behind -- `BaseAgent#recorded_chat`, which is the app's own
  # handle on it rather than a query this class invented.
  def receipts_for(generator)
    chat = generator.agent.recorded_chat
    return { answers: {}, calls: 0, input_tokens: 0, output_tokens: 0, prompts: {},
             missing_fields: [], cap_hits: [] } if chat.nil?

    messages = chat.messages.includes(:model).order(:id).to_a
    answered = messages.select { |message| message.role.to_s == "assistant" }
    asked = messages.select { |message| message.role.to_s == "user" }
    named = Eval::Realization::CALLS.first(answered.size)

    { answers: named.each_with_index.to_h { |call, index| [ call, raw_answer(answered[index]) ] }.compact,
      prompts: named.each_with_index.to_h { |call, index| [ call, asked[index]&.content ] }.compact,
      calls: answered.size,
      answered_by: answered.last&.model&.model_id,
      input_tokens: messages.sum { |message| message.input_tokens.to_i },
      output_tokens: messages.sum { |message| message.output_tokens.to_i },
      instructions: messages.find { |message| message.role.to_s == "system" }&.content,
      missing_fields: named.each_with_index.flat_map { |call, index| missing_fields(call, answered[index]) },
      cap_hits: named.each_with_index.flat_map { |call, index| cap_hits(call, answered[index]) } }
  end

  # WHAT A STORED ANSWER CANNOT SHOW, HALF ONE: A REQUIRED FIELD THAT NEVER
  # ARRIVED. Read off the provider's own JSON (`messages.content_raw`) against
  # the schema's own `required` list. `BaseAgent#missing_schema_keys` fails the
  # call when a top-level field is truly absent, which is the claim this checks
  # rather than assumes -- and the nested fields it does NOT check are where a
  # person with no `backstory` or a thing with no `description` comes from.
  def missing_fields(call, message)
    schema = schema_for(call)
    body = raw_answer(message)
    return [] if schema.nil? || body.nil?

    top = Array(schema.dig("schema", "required")).map(&:to_s)
                                                 .reject { |field| body[field].to_s.present? }
                                                 .map { |field| "#{call}.#{field}" }

    top + nested_missing(call, schema, body)
  end

  # THE FIELDS INSIDE AN ARRAY ENTRY, which the top-level check cannot see and
  # which the registries refuse a whole person or a whole thing over
  # (`Character::Registry#creation_refusal`). A room that lost its cast because
  # every sheet came back without a `fears` is a room the top-level check would
  # have called clean.
  def nested_missing(call, schema, body)
    properties = schema.dig("schema", "properties") || {}

    properties.flat_map do |field, rules|
      required = Array(rules.dig("items", "required")).map(&:to_s)
      next [] if required.empty?

      Array(body[field]).each_with_index.flat_map do |entry, index|
        next [] unless entry.is_a?(Hash)

        required.reject { |name| entry[name].to_s.present? }.map { |name| "#{call}.#{field}[#{index}].#{name}" }
      end
    end
  end

  # AND HALF TWO: A FIELD THAT ARRIVED AT ITS CAP, which is the provider cutting
  # the answer off rather than the model finishing it
  # (`SanitizesGeneratedText::TruncatedTextError`, and its header for why an
  # exact hit is truncation rather than a coincidence). It costs a person their
  # whole sheet here -- `Character::Registry#create_one` rescues the truncation
  # and refuses the row -- so it is worth its own figure rather than being read
  # off the refusals.
  def cap_hits(call, message)
    schema = schema_for(call)
    body = raw_answer(message)
    return [] if schema.nil? || body.nil?

    properties = schema.dig("schema", "properties") || {}
    properties.flat_map { |field, rules| capped(call, field, rules, body[field]) }
  end

  def capped(call, field, rules, value)
    cap = rules["maxLength"]
    return [ "#{call}.#{field}" ] if cap && value.to_s.length >= cap

    inner = rules.dig("items", "properties") || {}
    return [] if inner.empty?

    Array(value).each_with_index.flat_map do |entry, index|
      next [] unless entry.is_a?(Hash)

      inner.filter_map do |name, sub|
        limit = sub["maxLength"]
        "#{call}.#{field}[#{index}].#{name}" if limit && entry[name].to_s.length >= limit
      end
    end
  end

  # `RubyLLM::Schema` builds its JSON on an INSTANCE, not on the class -- the
  # class method exists and raises. Built fresh each time; it is a hash literal.
  def schema_for(call)
    klass = SCHEMAS[call]
    klass && klass.new.to_json_schema.deep_stringify_keys
  end

  def raw_answer(message)
    body = message&.content_raw
    body = JSON.parse(body) if body.is_a?(String)
    body.is_a?(Hash) ? body : nil
  rescue JSON::ParserError
    nil
  end
end
