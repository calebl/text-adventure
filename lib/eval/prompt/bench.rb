# THE CORPUS, PLAYED THROUGH THE REAL TURN LOOP, ONE CALL A CASE.
#
# `Playthrough::Turn#play` runs whole, on a staged position, with ONE thing
# replaced: the classifier. A case declares the answer the classifier would have
# given and `Eval::Prompt::Bench::FixedClassifier` returns it, so the turn takes
# the branch the app chooses, writes the row the app writes, and builds the
# prompt the app builds -- `Playthrough::Moment` and `Playthrough::Turn`'s own
# fact sentences, not a copy of them here. What is measured is the prose that
# comes back.
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
# ITS OWN COPY OF THE WORLD PER CASE, THROUGH THE STAGING SEAM AND NOT AROUND
# IT. A case moves rows -- a `take` takes, a `drop` drops, a `move` moves -- so
# two cases sharing one staged position would not be two cases. Each one is
# therefore staged on its own: `Eval::Classifier::Stage.open` loads that
# position's world, walks its setup lines offline, and rolls the whole thing
# back when the passage and the facts have been read out into Ruby.
#
# THERE IS EXACTLY ONE STAGING SEAM AND THIS CLASS OPENS NO TRANSACTION OF ITS
# OWN, which is deliberate: `Stage.open`'s `requires_new` block is due to be
# swapped for a pinned connection, and a bench that had rolled its own savepoint
# around each case would be a second place to fix. Both benches call the one
# entry point.
#
# AND IT IS THE SHORTEST LOCK EITHER BENCH TAKES, which is PR 119's lesson taken
# one step further. SQLite gives one writer: the classifier bench holds a write
# transaction for a whole pass, and a pass here would be several minutes with a
# provider round trip inside every one of them. Per case it is one call, and a
# seed load offline costs milliseconds against it.
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
# AND THE FIRST CALL IS ITS OWN FIGURE. Every arm gets one warm call before its
# first pass, timed, reported as `first call` and excluded from the latencies --
# so the figures the board prints are WARM-CACHE FIGURES and say so.
class Eval::Prompt::Bench
  # THE CLASSIFIER'S ANSWER, DECIDED BY THE CORPUS. A subclass rather than a
  # stub object, because `Playthrough::Turn` asks it for two more things than
  # `#classify` -- `#agent`, to file the turn's conversations under the scene,
  # and `#offered_for`, to build a refusal -- and a double that answered those
  # differently would be a second engine.
  class FixedClassifier < Playthrough::Classifier
    def initialize(playthrough, intent)
      super(playthrough)
      @intent = intent
    end

    def classify(_command) = @intent
  end

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
                        :instructions, :prompt, :missing_fields, :cap_hits, :error) do
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
        prompt:, missing_fields:, cap_hits:, error: }
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
    passes = []
    warmups = []

    arms.each do |arm|
      arm.pinned do
        warmups << warm(arm)
        (1..reps).each { |rep| passes << play(arm, rep) }
      end
    end

    Eval::Prompt::Result.new(
      corpus_size: corpus.size, corpus_digest: Eval::Prompt.digest(corpus),
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
  # into Ruby before `Stage.open` rolls the copy back, because after that there
  # is nothing left to read.
  def read(kase, arm, rep)
    Eval::Classifier::Stage.open([ corpus.position(kase.position) ],
                                 label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true) do |stages|
      play_case(kase, stages.fetch(kase.position), arm, rep)
    end
  end

  def play_case(kase, standing, arm, rep)
    playthrough = standing.playthrough
    story = playthrough.story
    intent = intent_for(kase, standing)
    from = playthrough.current_location

    turn = Playthrough::Turn.new(playthrough)
    turn.instance_variable_set(:@classifier, FixedClassifier.new(playthrough, intent))

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      scene = turn.play(kase.typed)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      receipts = receipts_for(scene)

      Reading.new(
        kase: kase, arm: arm.id, rep: rep, story: story.title, pass: receipts[:pass],
        text: scene&.description.to_s, facts: facts_after(kase, intent, playthrough.reload, from),
        seconds: elapsed, input_tokens: receipts[:input_tokens], output_tokens: receipts[:output_tokens],
        calls: receipts[:calls], answered_by: receipts[:answered_by],
        instructions: receipts[:instructions], prompt: receipts[:prompt],
        missing_fields: receipts[:missing_fields], cap_hits: receipts[:cap_hits], error: nil
      )
    rescue StandardError => error
      # A FAILED CALL HAS NO LATENCY, deliberately: how long it took to fail is
      # a fact about the failure and not about how fast this model answers.
      Reading.new(kase: kase, arm: arm.id, rep: rep, story: story.title, pass: kase.pass,
                  text: nil, facts: {}, seconds: nil, input_tokens: 0, output_tokens: 0,
                  calls: 0, answered_by: nil, instructions: nil, prompt: nil,
                  missing_fields: [], cap_hits: [], error: "#{error.class}: #{error.message}")
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

  # WHAT THE TURN COST AND WHAT IT WAS TOLD, read off the conversation it left
  # behind -- the same records `Playthrough::Feedback#provenance_for` reads, for
  # the same reason: they are the app's own account of the call rather than this
  # class's.
  def receipts_for(scene)
    return { pass: nil, calls: 0, input_tokens: 0, output_tokens: 0 } if scene.nil?

    messages = scene.messages.includes(:model, :chat).sort_by(&:id)
    answered = messages.select { |message| message.role.to_s == "assistant" }
    prose = answered.select { |message| Eval::Prompt::PASSES.include?(message.chat&.purpose) }
    kept = prose.last
    chat = kept&.chat

    { pass: chat&.purpose,
      calls: answered.size,
      answered_by: kept&.model&.model_id,
      input_tokens: messages.sum { |message| message.input_tokens.to_i },
      output_tokens: messages.sum { |message| message.output_tokens.to_i },
      instructions: chat&.messages&.find_by(role: "system")&.content,
      prompt: chat && chat.messages.where(role: "user").order(:id).last&.content,
      missing_fields: missing_fields(chat, kept),
      cap_hits: cap_hits(chat, kept) }
  end

  # WHAT STORED PROSE CANNOT SHOW, HALF ONE: A REQUIRED FIELD THAT NEVER
  # ARRIVED. Only a schema'd pass has any -- the narrator is the app's one
  # documented unschema'd call -- so this is the arrival's figure, read off the
  # provider's own JSON (`messages.content_raw`) against the schema's own
  # `required` list. `BaseAgent#missing_schema_keys` fails the call when a field
  # is truly absent, which is the claim this checks rather than assumes.
  def missing_fields(chat, message)
    schema = schema_for(chat)
    body = raw_answer(message)
    return [] if schema.nil? || body.nil?

    # `.map(&:to_s)`, because `deep_stringify_keys` stringifies KEYS and not the
    # values inside an array -- so `required` comes back as symbols against a
    # body whose keys are strings, and every field read as absent. Measured: 24
    # phantom omissions on the first 90-case run, two per arrival.
    Array(schema.dig("schema", "required")).map(&:to_s).reject { |field| body[field].to_s.present? }
  end

  # AND HALF TWO: A FIELD THAT ARRIVED AT ITS CAP, which is the provider cutting
  # the answer off rather than the model finishing it
  # (`SanitizesGeneratedText::TruncatedTextError`, and its header for why an
  # exact hit is truncation rather than a coincidence). `Scene::Generator` does
  # NOT pass its caps to the sanitizer, so this is measured here rather than
  # raised there -- and measuring it is the point: `truncated_prose` reads the
  # stored passage and can only see a cut that left a sentence hanging.
  def cap_hits(chat, message)
    schema = schema_for(chat)
    body = raw_answer(message)
    return [] if schema.nil? || body.nil?

    Array(schema.dig("schema", "properties")).filter_map do |field, rules|
      cap = rules["maxLength"]
      next if cap.nil?

      field if body[field].to_s.length >= cap
    end
  end

  # The JSON schema one pass sends, by purpose. A map rather than a lookup on
  # the agent, because the agent is gone by the time this runs and the pass is
  # what a stored row records.
  SCHEMAS = { "arrival" => Scene::Schema }.freeze

  # `RubyLLM::Schema` builds its JSON on an INSTANCE, not on the class -- the
  # class method exists and raises. Built fresh each time; it is a hash literal.
  def schema_for(chat)
    klass = SCHEMAS[chat&.purpose]
    klass && klass.new.to_json_schema.deep_stringify_keys
  end

  def raw_answer(message)
    body = message&.content_raw
    body.is_a?(String) ? JSON.parse(body) : body
  rescue JSON::ParserError
    nil
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
