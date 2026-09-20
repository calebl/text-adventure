# THE FIRST READER A FREE-TYPED LINE MEETS WHEN THIS ENVIRONMENT HAS A SYSTEM
# ONE KEY: one request of ten questions, and then the ENGINE deciding what the
# answers mean.
#
# THE WHOLE POINT IS THE SECOND HALF. A System One request is still a model
# call, so it can be WRONG -- what it cannot be is OUT OF BOUNDS, because every
# question it answers is a Choice over a set this app closed
# (`Playthrough::Classifier::Request`) or a probability. Nothing here asks a
# model what should happen. It asks it to pick from a set the app built, and
# then this class acts on records. That is the project's standing rule, applied
# to a second provider.
#
# WHAT COMES BACK, AND WHAT IS READ:
#
#   intent                 the one action; every other answer is read in its light
#   target_<intent>        ONLY the chosen intent's target. The other six target
#                          answers are discarded unread -- the dispatcher pattern
#   also_named             narrowed HERE to the chosen intent's own set
#   target_present         a probability: is the thing asked for listed at all
#   named_more_than_one    a probability: does one intent reach for two records
#
# THE TWO FLAGS, AND WHAT THEY DO. If `named_more_than_one` reads at or above
# `TWO_NAME_THRESHOLD`, or `target_present` reads below `PRESENCE_THRESHOLD`,
# this class answers NIL and the line goes on to the Mistral classifier call
# exactly as it runs today -- same instructions, same prompt, same schema.
# Sequentially, and only for those lines: about a quarter of the lines that
# reach a model make two calls, and a parallel call would pay for the expensive
# model on every turn and throw most of it away.
#
# WHAT ESCALATION IS NOT. It is not a failure and not a refusal: the line is
# read by the reader that reads that shape of line better.
#
# WHAT IT HAS ACTUALLY MEASURED, AND IT IS NOW AHEAD OF THE INCUMBENT. The
# figures this file once quoted were a SIMULATION over stored readings, and the
# first run as it shipped came in two points BELOW the model call alone. That
# was a defect in the request, not a property of the cascade. With the request
# restored -- both halves of it -- four repetitions on the same 343 lines read
# .9388-.9417 whole-answer against .9329-.9359 for the same model call alone,
# with 12-13 closed-set misses against 15-16 and 27-28 of 32 second names
# against 27. `rake eval:classifier_compare` calls that REAL on accuracy,
# refusal agreement and closed-set misses.
# `db/eval/classifier-cascade-state-20260919` is the reading, with its rows.
#
# THE ONE FIGURE THAT IS REAL WORSE IS P95 LATENCY, and it is worse by
# construction: an escalated line makes two calls in sequence and about a
# quarter of the lines escalate. The MEDIAN turn got faster (0.41s against
# 0.55s) and the worst turn in twenty got slower (1.29s against 0.96s). That is
# the trade this class is, and it must be stated that way rather than averaged.
#
# WHAT THE GAP TURNED OUT TO BE, because the answer is the useful part. The
# shipped cascade escalated about 61 lines a repetition where the arm the design
# of record was chosen on escalates 90-93. Three things it was NOT, each ruled
# out by a measurement rather than by argument:
#
#   * NOT THIS CLASS. Replaying the scored arm's own stored answers through the
#     composition below escalates 90, 90, 91, 93 -- the simulation line for
#     line. Pinned by `Playthrough::Classifier::CascadeTest` and
#     `Playthrough::ClassifierPathsTest`.
#   * NOT A CODE-FIRST GATE. The scored arm settled 65 of the 343 lines in code
#     before it sent anything. On those same 65 lines this class escalated ZERO,
#     in every repetition -- so the denominators already agreed.
#   * NOT THE REQUEST WORDING. It WAS an earlier revision and it has been
#     restored, and that reading was NOISE on every figure.
#
# IT WAS THE STATE. `Playthrough::Classifier::State` differed from the measured
# state in three ways -- `player_action` second rather than last, an empty block
# left out rather than sent empty, and `valid_intents` in enum order rather than
# leading with the block's own intent. Correcting them makes all twelve staged
# positions byte-identical to the arm's stored requests, and takes the
# escalation rate from 60-62 to 87-91. That file's header now carries the rule;
# `Playthrough::Classifier::StateTest` compares a staged position byte for byte.
#
# WHY A WORDING CHANGE TO `also_named` CANNOT BE JUDGED BY THE SECOND-NAME
# COUNT ALONE, which is the thing that made the diagnosis hard. 117 of the 128
# readings whose label carries a second name ESCALATE -- the two-name flag sends
# them to the model call -- so this class's own `also_named` answer is read on
# about one line in twelve of the ones that question was measured on. Restoring
# its wording moved the count by nothing; restoring the state moved it from
# 24-25 to 27-28, because the flag started firing where it was supposed to.
#
# NOTHING HERE CAN BLOCK A TURN. Every way the provider can fail is
# `SystemOneAgent::Unavailable`, and every one of them lands on the same line as
# a flag: make the call that would have been made anyway. See `#read`.
class Playthrough::Classifier::Cascade
  # THE PRESENCE CUT, AND ITS PROVENANCE -- restated here because this is the
  # file the number lives in and a threshold quoted without its provenance is a
  # number somebody nudged.
  #
  # 0.15 was CHOSEN on the fixed 80-line trial slice, CONFIRMED on the 263-line
  # holdout, and NEVER TUNED on the corpus that scores it. It is engine policy
  # applied to readings already paid for, so adopting it sent nothing.
  #
  # Live readings MAY re-pick it, on the same terms: chosen on held-out turns
  # the new value is not then scored against, and recorded as a change to a
  # measured rule -- the old value, the new one, the turns it was chosen on and
  # the reading either side. See EVALUATION.md.
  PRESENCE_THRESHOLD = 0.15

  # The two-name cut, unchanged from the shape it was measured in. A Noul at 0.5
  # is the point where yes and no are equally likely, which is the only
  # defensible default for a flag whose job is "ask the other reader".
  TWO_NAME_THRESHOLD = 0.5

  attr_reader :classifier

  # `path` is what `scenes.resolved_by` gets, and it is nil until `#read` has
  # run. One of `Playthrough::Classifier::PATHS`, never `model` -- that value
  # means this class did not run at all.
  attr_reader :path

  # THE TWO NOUL READINGS THEMSELVES, kept beside `#path` rather than only
  # acted on. Nil until `#read` has run, and nil forever on a line the
  # provider never answered (`typed_model_unavailable`) -- there is no reading
  # to keep in that case. Read-only: nothing here changes what `#compose`
  # decides. `Eval::Classifier::Bench` is the reason this exists -- a bench
  # that could only see WHICH path a line took and not WHAT the two flags
  # actually read could never reconcile a composition question line by line.
  attr_reader :target_present, :named_more_than_one

  # WHICH SYSTEM ONE TRANSPORT ANSWERED THIS LINE, as `SystemOneAgent#transport_name`
  # reports it. Nil until `#read` has run. Kept here rather than as a new
  # `scenes` column: `scenes.resolved_by` already names the typed path family,
  # a typed call leaves no chat receipt, and a replay's kept rows are where a
  # transport comparison is actually read.
  attr_reader :system_one_transport

  # `agent` is the seam a test and the offline engine sweep stand a fixture in
  # at. Nil is the real provider.
  def initialize(classifier, agent: nil)
    @classifier = classifier
    @agent = agent
  end

  # THE INTENT THIS LINE COMPOSES TO, OR NIL FOR "ASK THE OTHER READER".
  #
  # Nil is returned for exactly two reasons and `#path` tells them apart: a flag
  # fired (`typed_model_escalated`), or the provider could not be believed
  # (`typed_model_unavailable`). The caller does the same thing with both, which
  # is the point -- neither is an engine refusal, and neither costs the player a
  # turn.
  def read(command)
    state = Playthrough::Classifier::State.new(classifier, command)
    asked = agent
    @system_one_transport = asked.respond_to?(:transport_name) ? asked.transport_name : nil
    answers = asked.ask_questions(state: state.to_h,
                                  questions: Playthrough::Classifier::Request.new(state).to_h)
    compose(state, answers)
  rescue SystemOneAgent::Unavailable => e
    # COUNTED, AND WITHOUT THE BODY OR THE KEY. A run of these is how an outage
    # is noticed at all, because the game keeps playing through every one of
    # them; `scenes.resolved_by` is the durable half of the same signal.
    Rails.logger.warn { "[system_one] #{e.class}: #{e.message} -- this line goes to the model call" }
    @path = "typed_model_unavailable"
    nil
  end

  private

  def agent = @agent ||= SystemOneAgent.new(purpose: "classifier")

  def compose(state, answers)
    action = answers.choice("intent").to_sym
    presence = answers.noul("target_present")
    two_name = answers.noul("named_more_than_one")
    @target_present = presence
    @named_more_than_one = two_name

    if escalate?(presence: presence, two_name: two_name)
      @path = "typed_model_escalated"
      return nil
    end

    @path = "typed_model"
    # THE PRESENCE GATE, AND IT DROPS BOTH NAMES TOGETHER OR NEITHER. Under the
    # escalation rule above a low reading has already left this method, so this
    # cannot fire today -- it is written anyway because it is the rule that
    # keeps `nothing (and a record)` unreachable, and a future rule that
    # escalated on the two-name flag alone would reach it on its first line.
    # That shape is incoherent (the turn acts on nothing and announces what it
    # left undone) and the engine has never emitted it.
    present = presence >= PRESENCE_THRESHOLD
    target = present ? chosen_target(state, answers, action) : nil
    also = present ? chosen_also(state, answers, action, target) : nil

    intent_for(action, target, also)
  end

  # THE TWO FLAGS, IN ONE PLACE. A method rather than an expression inline
  # because it is the whole of the cascade's rule and the one thing a later
  # measurement is expected to re-pick: the presence-alone variant is this
  # method with the first clause removed, and it is already measured
  # (.9242-.9329 whole-answer, escalation .1691-.1808) should anybody want it.
  def escalate?(presence:, two_name:)
    two_name >= TWO_NAME_THRESHOLD || presence < PRESENCE_THRESHOLD
  end

  # ONLY THE CHOSEN INTENT'S TARGET. A question that was not sent -- an action
  # with no records here -- resolves to nothing by construction, which is the
  # same answer and one fewer thing to get wrong.
  def chosen_target(state, answers, action)
    id = Playthrough::Classifier::Request.target_id(action)
    return nil unless answers.asked?(id)

    state.record_for(answers.choice(id))
  end

  # THE SECOND NAME, NARROWED TO THIS INTENT'S OWN SET. The question offers every
  # record in the position, because it is answered before anybody has decided
  # what the line is; an answer naming a record this action cannot reach is not
  # a second act on this line, and the engine drops it. Dropped too when it is
  # the target, for the reason `Playthrough::Classifier#also_record` states: one
  # record answering to two names is not two things.
  def chosen_also(state, answers, action, target)
    return nil unless answers.asked?("also_named")

    record = state.record_for(answers.choice("also_named"))
    return nil if record.nil? || record == target
    return nil unless state.offers?(action, record)

    record
  end

  # THE SLOTS `Playthrough::Classifier::Intent` HOLDS A RESOLVED RECORD IN, read
  # out of the one table that owns them.
  def intent_for(action, target, also)
    # A `use` resolves to the whole closed attempt token, exactly as the model
    # call does, and its second name is the OTHER attempt's own subject -- never
    # a part already bound inside the attempt this line is performing.
    if action == :use
      extra = also&.subject
      extra = nil if target&.records&.include?(extra)
      return Playthrough::Classifier::Intent.new(action: action, physical: target, also_named: extra)
    end

    slot = Playthrough::Classifier::SLOTS[action]
    return Playthrough::Classifier::Intent.new(action: action) if slot.nil?

    Playthrough::Classifier::Intent.new(action: action, also_named: also, **{ slot => target })
  end
end
