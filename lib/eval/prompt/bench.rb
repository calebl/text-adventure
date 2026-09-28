# THE CORPUS, PLAYED BY THE ENGINE THE GAME PLAYS, ONE CALL A CASE.
#
# Each case is one submitted line played by the Rust engine
# (`Playthrough::Requests.submit_fixed`), whole, on a staged position, with ONE
# thing fixed: the reading. A case declares the answer the classifier would
# have given, and the engine takes it wherever it would have asked the
# classifier (`turn::Fixed`), so the turn takes the branch the engine chooses,
# writes the rows the engine writes, and builds the prompt the engine builds --
# its moment and its fact sentences, not a copy of them here. Every other call
# the turn makes comes back to this bench as the engine's request, and the
# bench sends it (`Eval::EngineCalls::Sender`). What is measured is the prose
# that comes back.
#
# WHY THE CLASSIFIER IS THE THING REPLACED, and only it. It is the one call in a
# turn that is not the thing being measured: leaving it in would put a second
# model between the case and the passage, so a case would sometimes take a
# branch its facts were not written for and the run would be measuring two
# models at once. Replacing it also makes a case FIXED -- the same branch, the
# same item, every repetition -- which is the whole premise of a single-turn
# bench. `Eval::Classifier` measures that call, on its own corpus.
#
# ONE CALL A CASE, AND THE CORPUS VALIDATOR IS WHAT KEEPS IT THAT WAY. A stub
# destination would call `Location::Generator`, a readable thing with no words
# would call `Item::Inscriber`, and a `talk` costs two calls and is not measured
# at all -- see `Eval::Prompt::Corpus#extra_call_problems` and
# `Eval::Prompt::UNSUPPORTED_ACTS`. `Reading#calls` counts what really happened
# and the board says so if it was ever more than one.
#
# AN ENDING CASE IS THE ONE SHAPE THAT BUYS TWO, and it is not an oversight in
# the paragraph above: an ending happens on the line that concludes the arc,
# so the take or the look or the arrival is narrated first and the ending is
# written second. `Reading#calls` counts only the prose calls that are not a
# prelude to the one scored -- so `extra_calls` still reads 0 and the figure
# that tells the truth about the spend is the estimate
# (`Eval::Prompt::PER_CALL["ending"]`, and `Corpus::Case#calls`).
#
# ITS OWN COPY OF THE WORLD PER CASE, THROUGH THE STAGING SEAM AND NOT AROUND
# IT. A case moves rows -- a `take` takes, a `drop` drops, a `move` moves -- so
# two cases sharing one staged position would not be two cases. Each one is
# therefore staged on its own: `Eval::Classifier::Stage.on_file` loads that
# position's world on a scratch copy of this database, walks its setup lines
# offline, and deletes the copy when the passage and the facts have been read
# out into Ruby. A copy rather than a rolled-back transaction, because the
# engine plays on a connection of its own and reads only what is committed;
# nothing a case does ever reaches this database.
#
# SEVERAL REPETITIONS, BECAUSE ONE IS NOT A MEASUREMENT. This is prose at the
# app's own temperature and two identical runs disagree -- that finding is
# `Eval::Noise`'s and the whole reason `EVALUATION.md` reports a band. The
# default is `Eval::Noise::MIN_RUNS`, so a run taken at the default is a run a
# later comparison can give a verdict against.
#
# PER MODEL, ONE MODEL PER ARM, NOTHING BEHIND IT -- `Eval::Classifier::Arm`,
# shared rather than copied. Read its header for the three reasons a measurement
# wants the rotation off. `#rotated?` survives here as a guard, exactly as it
# does there.
#
# SERIAL, ON PURPOSE AND FOR NOW. `Eval::Concurrency` landed beside this
# (PR 124) and its header names this bench as the second caller, and the seam is
# already here: `Stage.open` runs inside a pinned connection, so the machinery
# is under every case. What is NOT here is a second call in flight, and the
# reason is a real design question rather than an oversight -- this bench stages
# ONE COPY OF THE WORLD PER CASE, so two cases in flight are two stagings in
# flight, and the isolation that buys is exactly what a `take` and a `drop`
# against one position need. Batching them means staging per POSITION and
# isolating the cases some other way, which is a decision about what a case is.
# The figures below are therefore serial figures: a latency here is what one
# player waits, with nothing queued behind it.
#
# AND THE FIRST CALL IS ITS OWN FIGURE. Every arm gets one warm call before its
# first pass, timed, reported as `first call` and excluded from the latencies --
# so the figures the board prints are WARM-CACHE FIGURES and say so.
class Eval::Prompt::Bench
  # THE NAME A FALLBACK IS FILED UNDER, and it is a class rather than a string
  # for the reason every other failure here is one: `Reading#error_class` splits
  # on colon-space and the board groups by what it finds, so a failure with no
  # name is a failure nobody can count.
  #
  # IT IS NEVER RAISED. `Scene::Ending` swallows every way its call can fail --
  # that is the whole design, the player gets an ending either way -- so from out
  # here a refused ending and a written one both come back as a Scene. What tells
  # them apart is the LABEL the engine wrote on the row: a `conclude` row is the
  # engine's own sentence and a `Scene::NARRATED_ENDING` row is the narrator's.
  #
  # AND A FALLBACK IS NOT A PASSAGE, which is why this exists at all: scoring the
  # engine's stored sentence as prose would put the app's own copy in the
  # numerator of every check and in the richness figure, and a refusal would read
  # as a clean run. Named as a failed call instead, which is what it is.
  class EndingFellBack < StandardError; end
  class RenderingFellBack < StandardError; end

  # WHAT ONE CASE CAME BACK AS, with the facts it was written against.
  #
  # `facts` is the moment as the RECORDS held it after the turn, built by asking
  # the app's own `Story::Audit` for the same lists it would read -- see
  # `#facts_after`. It is stored beside the passage so the checks can be run
  # again, offline and for nothing, without the calls being paid for a second
  # time: `Eval::Prompt::Scorer` reads exactly this and never a live record.
  #
  # `instructions` is the system message the prose call was given, which is what
  # `Playthrough::PromptVersion` digests, and `prompt` is the whole user prompt
  # -- kept for one designated case per shape (see `Eval::Prompt::Version`) and
  # dropped for the rest, because a hundred whole prompts is a megabyte of file
  # nobody reads.
  Reading = Data.define(:kase, :arm, :rep, :story, :pass, :text, :facts, :seconds,
                        :input_tokens, :output_tokens, :calls, :answered_by,
                        :instructions, :prompt, :missing_fields, :cap_hits, :error, :ending_request) do
    def initialize(ending_request: nil, **attributes) = super
    def id = kase.id
    def shape = kase.shape
    def act = kase.act
    def failed? = !error.nil?
    def held_out? = Eval::Prompt.held_out?(story)

    # WHY A CALL FAILED, as a class name -- `BaseAgent::RefusalError` reads
    # differently from a timeout and a count cannot tell them apart. Split on
    # colon-space, not on a colon: the class is usually namespaced.
    def error_class = error&.split(": ")&.first

    # THE MODEL DECLINED TO WRITE THE TURN. `BaseAgent#verify_not_refused!`
    # makes that a failed call, and with an arm of one there is nothing to
    # rotate to -- so it arrives here as a failure of a nameable class rather
    # than as prose. It is a figure of its own because it is the one failure
    # that is about the PROMPT: a passage nobody can read is the worst outcome
    # a prompt change can buy, and a rate that only counted defects would score
    # it as a clean run.
    def refused? = error_class == "BaseAgent::RefusalError"

    # THE PROVIDER ANSWERED WITH REAL-WORLD CRISIS RESOURCES. Never persisted,
    # never rotated, and counted apart from everything else -- see
    # `BaseAgent::CrisisResponseError` and `Playthrough::SafetyNotice`.
    def crisis? = error_class == "BaseAgent::CrisisResponseError"

    # THE GUARD, not a figure: with an arm of one there is nothing to rotate
    # to, so this is false on every reading of a healthy run.
    def rotated?
      return false if answered_by.nil?

      answered_by != Eval::Classifier::Arm.parse(arm).model
    end

    # ONE CASE, ONE CALL. More than one means a case bought a second model call
    # -- a stub realized, an inscription written -- which the corpus validator
    # exists to prevent and this is the check on it.
    def extra_calls = [ calls.to_i - 1, 0 ].max

    def to_h
      { id:, shape:, act: act.to_s, position: kase.position, story:, held_out: held_out?,
        typed: kase.typed, target: kase.target, pass:, text:, facts:,
        seconds: seconds&.round(4), input_tokens:, output_tokens:, calls:,
        answered_by:, instructions_digest: Playthrough::PromptVersion.of(instructions),
        prompt:, missing_fields:, cap_hits:, error:, ending_request: }.tap do |row|
          row[:human] = { "truthfulness" => nil, "next_beat_fit" => nil, "quality" => nil } if facts.key?("branch")
        end
    end
  end

  # WHAT THE FIRST CALL COST, once per arm. Reused from the classifier bench
  # rather than redefined: it is the same fact about the same thing.
  Warmup = Eval::Classifier::Bench::Warmup

  # ONE PASS OF THE WHOLE CORPUS ON ONE MODEL. Every figure it answers is
  # computed from the READINGS and their stored facts, which is what lets a set
  # loaded off disk answer the same questions -- see `Eval::Prompt::Result`.
  # STRING KEYS THROUGHOUT, because this hash is written to a file and read back
  # by `Eval::Prompt::Result::Stored`, and one shape has to serve both.
  Pass = Data.define(:arm, :rep, :readings) do
    def rows = readings.map { |reading| reading.to_h.transform_keys(&:to_s) }

    def to_h
      { "arm" => arm, "rep" => rep }.merge(Eval::Prompt::Result.figures_of(rows)).merge("readings" => rows)
    end

    # THE FORM EVERYTHING DOWNSTREAM READS. A live pass and a pass loaded off
    # disk are the same object from here on, which is what stops a figure being
    # computed two ways.
    def stored = Eval::Prompt::Result::Stored.new(to_h)
  end

  attr_reader :corpus, :arms, :reps, :io

  def initialize(corpus: Eval::Prompt.corpus, arms: nil, reps: Eval::Noise::MIN_RUNS, io: $stdout)
    @corpus = corpus
    @arms = Eval::Classifier::Arm.all(arms.presence || [ BaseAgent::REMOTE_MODEL_IDS.first ])
    @reps = reps
    @io = io
  end

  # Returns an `Eval::Prompt::Result`. A case whose call fails is recorded as a
  # failure and the pass keeps going: a provider dropping one call in a hundred
  # must not cost the whole run.
  def run
    request_identity = Eval::Prompt::RequestVersion.offline(corpus)[:request_identity]
    passes = []
    warmups = []

    arms.each do |arm|
      arm.pinned do
        warmups << warm(arm)
        (1..reps).each { |rep| passes << play(arm, rep) }
      end
    end

    ending = corpus.cases.all?(&:ending?) ? Eval::Prompt::EndingVersion.of(passes, corpus) : {}
    Eval::Prompt::Result.new(
      corpus_size: corpus.size, corpus_digest: Eval::Prompt.digest(corpus),
      request_identity: ending.fetch(:request_identity, request_identity),
      ending_requests: ending[:ending_requests],
      arms: arms.map(&:id), reps: reps, passes: passes.map(&:stored), warmups: warmups,
      **Eval::Prompt::Version.of(passes)
    )
  end

  private

  # ONE CALL BEFORE THE MEASUREMENT, TIMED AND THEN SET ASIDE. A real case on a
  # real position, because a warm-up that took a different path would warm a
  # different thing. Its duration is the cold start: for a hosted arm, the
  # connection setup and a cold route made visible as their own number rather
  # than hidden in the band.
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

    pass = Eval::Prompt::Bench::Pass.new(arm: arm.id, rep: rep, readings: readings)
    scored = Eval::Prompt::Scorer.new(pass.rows)
    io&.puts format("%3d passages, %2d flagged, %.1fs median%s%s",
                    readings.count { |reading| reading.text.present? }, scored.flags.size,
                    Eval.median(readings.filter_map(&:seconds)),
                    pass.readings.count(&:failed?).positive? ?
                      ", #{pass.readings.count(&:failed?)} FAILED" : "",
                    pass.readings.any?(&:rotated?) ? ", ROTATED -- THE PINNING FAILED" : "")
    pass
  end

  # ONE CASE, IN ITS OWN COPY OF ITS WORLD. Everything worth keeping is read out
  # into Ruby before `Stage.on_file` deletes the copy, because after that there
  # is nothing left to read.
  def read(kase, arm, rep)
    Eval::Classifier::Stage.on_file([ corpus.position(kase.position) ],
                                    label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                    roots: Eval::Prompt::WORLD_ROOTS, pinned: true) do |stages, file|
      play_case(kase, stages.fetch(kase.position), arm, rep, file)
    end
  end

  # The purpose the engine files a game's last paragraph under.
  ENDING = "ending".freeze

  # THE CASE, PLAYED BY THE ENGINE ON THE STAGED COPY AT `file`, its calls
  # answered by `answering` (`Eval::EngineCalls`): the arm's own sender on a
  # paid pass, and fixed words when the request itself is all a caller wants
  # (`Eval::Prompt::RequestVersion`).
  def play_case(kase, standing, arm, rep, file, answering: Eval::EngineCalls::Sender.new(standing.playthrough))
    playthrough = standing.playthrough
    story = playthrough.story
    intent = intent_for(kase, standing)
    from = playthrough.current_location
    @ending_request = nil
    cut = { missing_fields: [], cap_hits: [] }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      answer = Playthrough::Requests.submit_fixed(file, playthrough, kase.typed, token: SecureRandom.uuid,
                                                  fixed: { action: kase.act.to_s, target: kase.target.presence }) do |call|
        scaffold_ending!(playthrough, call) if kase.ending? && call["purpose"] == ENDING
        answering.call(call)
      end
      failure = answering.respond_to?(:failure) ? answering.failure : nil
      if (error = answer["error"])
        raise failure || Playthrough::RustEngine::EngineError.new(error.fetch("kind"), error.fetch("message"))
      end

      scene = answer.dig("turned", "scene") && Scene.find(answer.dig("turned", "scene"))
      # Recovery completes engine effects despite an unavailable renderer.
      # Adapt that receipt to the existing failed-call row; engine-authored
      # fallback words must never become model prose or change refusal counts.
      # What the provider sent is still on its receipt, and an arrival refused
      # for reaching its cap is exactly what `cap_hits` counts, so the failed
      # row keeps both halves of `#cap_hits`' figure.
      if scene&.engine_fallback?
        cut = receipts_for(answering.receipts).slice(:missing_fields, :cap_hits)
        raise(failure || RenderingFellBack.new("the renderer did not answer, so the engine's words stand"))
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      receipts = receipts_for(answering.receipts)
      # THE ENDING THAT FELL BACK, read off the row the engine labelled -- see
      # `EndingFellBack`. Nothing else in this method asks the game what happened;
      # this one has to, because the pass being measured answers a Scene whether
      # or not a model wrote it.
      if kase.ending? && scene&.engine_authored?
        return Reading.new(
          kase: kase, arm: arm.id, rep: rep, story: story.title, pass: kase.pass,
          text: nil, facts: {}, seconds: nil, input_tokens: receipts[:input_tokens],
          output_tokens: receipts[:output_tokens], calls: receipts[:calls], answered_by: nil,
          instructions: nil, prompt: nil, missing_fields: [], cap_hits: [],
          error: "#{EndingFellBack}: the ending call did not answer, so the engine's stored sentence stands"
        )
      end

      Reading.new(
        kase: kase, arm: arm.id, rep: rep, story: story.title, pass: receipts[:pass],
        text: scene&.description.to_s, facts: facts_after(kase, intent, playthrough.reload, from),
        seconds: elapsed, input_tokens: receipts[:input_tokens], output_tokens: receipts[:output_tokens],
        calls: receipts[:calls], answered_by: receipts[:answered_by],
        instructions: receipts[:instructions], prompt: receipts[:prompt],
        missing_fields: receipts[:missing_fields], cap_hits: receipts[:cap_hits], error: nil,
        ending_request: @ending_request
      )
    rescue StandardError => error
      # A FAILED CALL HAS NO LATENCY, deliberately: how long it took to fail is
      # a fact about the failure and not about how fast this model answers.
      Reading.new(kase: kase, arm: arm.id, rep: rep, story: story.title, pass: kase.pass,
                  text: nil, facts: {}, seconds: nil, input_tokens: 0, output_tokens: 0,
                  calls: 0, answered_by: nil, instructions: nil, prompt: nil,
                  **cut, error: "#{error.class}: #{error.message}")
    end
  end

  # THE ANSWER THE CLASSIFIER WOULD HAVE GIVEN, built out of the records the
  # closed sets really hold. `Playthrough::Classifier#offered_for` is the one
  # reader, so a case cannot name a record the action does not read against --
  # and the corpus validator has already refused a case that tried.
  def intent_for(kase, standing)
    record = kase.target.presence && standing.offered_for(kase.act).find do |candidate|
      names_of(candidate).any? { |name| name.to_s.casecmp?(kase.target.to_s) }
    end

    raise Eval::Prompt::Corpus::Invalid, "#{kase.id}: #{kase.target.inspect} is not in reach" if
      kase.target.present? && record.nil?

    Playthrough::Classifier::Intent.new(
      action: kase.act,
      destination: record.is_a?(Location) ? record : nil,
      speaker: record.is_a?(Character) ? record : nil,
      item: record.is_a?(Item) ? record : nil
    )
  end

  # WHAT THE TURN COST AND WHAT IT WAS TOLD, out of the receipt of every call
  # it made (`Eval::EngineCalls::Receipt`): the pass that answered is the last
  # prose pass, what it was told is what the engine asked, and what it cost is
  # every call's conversation.
  def receipts_for(calls)
    kept = calls.select { |receipt| Eval::Prompt::PASSES.include?(receipt.purpose) }.last

    { pass: kept&.purpose,
      calls: kept&.purpose == ENDING ? 1 : calls.size,
      answered_by: kept&.answered_by,
      input_tokens: calls.sum(&:input_tokens),
      output_tokens: calls.sum(&:output_tokens),
      instructions: kept&.system,
      prompt: kept&.user,
      missing_fields: missing_fields(kept),
      cap_hits: cap_hits(kept) }
  end

  # WHAT STORED PROSE CANNOT SHOW, HALF ONE: A REQUIRED FIELD THAT NEVER
  # ARRIVED. Only a schema'd pass has any -- the narrator is the app's one
  # documented unschema'd call -- so this is the arrival's figure, read off the
  # provider's own stored JSON against the schema's own
  # `required` list. `BaseAgent#missing_schema_keys` fails the call when a field
  # is truly absent, which is the claim this checks rather than assumes.
  def missing_fields(receipt)
    schema = receipt&.schema
    body = receipt&.raw
    return [] if schema.nil? || body.nil?

    # `.map(&:to_s)`, because a schema's `required` can come back as symbols
    # against a body whose keys are strings, and every field read as absent.
    # Measured: 24 phantom omissions on the first 90-case run, two per arrival.
    Array(schema.dig("schema", "required")).map(&:to_s).reject { |field| body[field].to_s.present? }
  end

  # AND HALF TWO: A FIELD THAT ARRIVED AT ITS CAP, which is the provider cutting
  # the answer off rather than the model finishing it
  # (`SanitizesGeneratedText::TruncatedTextError`, and its header for why an
  # exact hit is truncation rather than a coincidence). The engine refuses such
  # an arrival and tells it in its own words, so the case is a failed row --
  # and this still counts it off the provider's receipt, because measuring it is
  # the point: `truncated_prose` reads the stored passage and can only see a
  # cut that left a sentence hanging.
  def cap_hits(receipt)
    schema = receipt&.schema
    body = receipt&.raw
    return [] if schema.nil? || body.nil?

    Array(schema.dig("schema", "properties")).filter_map do |field, rules|
      cap = rules["maxLength"]
      next if cap.nil?

      field if body[field].to_s.length >= cap
    end
  end

  # THE ENDING'S SCAFFOLD, from the rows as they stand when the ending is
  # asked (`Eval::Prompt::EndingVersion.scaffold`): the closing scene is the
  # game's current one, and the prelude the scene before it.
  def scaffold_ending!(playthrough, call)
    closing = Playthrough.find(playthrough.id).current_scene
    outcome = Playthrough::Ending.find_by!(playthrough_id: playthrough.id).quest_outcome
    @ending_request = Eval::Prompt::EndingVersion.scaffold(playthrough, outcome: outcome, prelude: closing.previous_scene,
                                                                        prompt: call.fetch("user"))
  end

  # THE MOMENT AS THE RECORDS HELD IT, AFTER THE TURN, and every list in it is
  # asked of `Story::Audit` rather than rebuilt: the checks read these lists off
  # a live story, so a bench that assembled its own versions of them would be
  # scoring a different world from the one `rake game:score` scores. Only the
  # three facts a single turn owns -- what it acted on, where it came from and
  # what is written on the thing -- are read here.
  def facts_after(kase, intent, playthrough, from)
    story = playthrough.story
    audit = Story::Audit.new(story)
    room = playthrough.current_location
    item = intent.item

    { "room" => room&.name,
      "from" => from&.name,
      "moved" => (from&.id != room&.id),
      "protagonist" => Story::Audit::Prose.protagonist_names(story.protagonist),
      "places" => audit.send(:place_names),
      "exits" => playthrough.exits.map(&:name),
      "present" => (Scene::Generator.characters_present(room) - [ story.protagonist ].compact).map(&:fullname),
      "floor" => room ? playthrough.items_lying_in(room).map(&:name) : [],
      "carried" => playthrough.carried.map(&:name),
      "elsewhere" => audit.send(:items_elsewhere).map { |row|
        { "name" => row.name, "whereabouts" => row.whereabouts, "here" => row.location_id == room&.id }
      },
      "action" => kase.act.to_s,
      "item" => item&.name,
      "inscription" => (item&.inscription if item.respond_to?(:inscription)) }
  end

  def names_of(record)
    return [ record.fullname, record.nickname ].compact_blank if record.respond_to?(:fullname)

    [ record.name ].compact_blank
  end
end
