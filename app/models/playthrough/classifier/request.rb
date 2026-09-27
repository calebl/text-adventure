# THE TEN QUESTIONS ONE TYPED LINE IS ASKED, plus the one that says whether the
# thing it asked for is here at all.
#
#   intent            one Choice over `Playthrough::IntentSchema::INTENTS`
#   target_<action>   one Choice per action that has records, over THAT ACTION'S
#                     closed set plus `nothing` -- seven of them at a full
#                     position, fewer in a bare room
#   also_named        one Choice over every record in the position, plus nothing
#   named_more_than_one   a Noul: does one intent reach for two records
#   target_present        a Noul: is the thing asked for listed at all
#
# A TARGET QUESTION PER ACTION IS WHAT MAKES AN OUT-OF-LIST ANSWER STRUCTURALLY
# IMPOSSIBLE, and that is the reason for the shape rather than a side effect of
# it. The app's own three-field schema holds ONE `target` over the union of every
# list, so a model could answer `take` with the name of a doorway and the engine
# had to null it; over four repetitions of each measured arm that happened 7-12
# times a run. Here the option set IS the intent's own set, and it happened zero
# times in every repetition of every arm that used this shape.
#
# The engine then reads only the chosen intent's answer and discards the other
# six unread -- the vendor's own dispatcher pattern, and the project's own rule
# about who decides. See `Playthrough::Classifier::Cascade`.
#
# A QUESTION WHOSE RECORD SET IS EMPTY IS NOT SENT. A room with nothing lying in
# it has no `target_take` to ask, and that intent resolves to nothing BY
# CONSTRUCTION rather than by an answer -- which is cheaper and also stricter
# than asking a question whose only honest option is `nothing`.
#
# THE WORDING IS THE MEASURED ARM'S WORDING, AND THAT IS THE RULE. Every
# sentence below is the text of the arm the design of record was chosen on --
# the collective-word pass, with the presence question appended -- and
# `test/fixtures/files/scored_classifier_request.json` is that arm's own stored
# request, kept in the repository so the claim is checkable rather than
# remembered. `RequestTest` builds the position that request was sent for and
# compares every instruction string against it.
#
# SO CHANGING A SENTENCE HERE IS A PROMPT CHANGE AND NEEDS A BASELINE EITHER
# SIDE OF IT -- `EVALUATION.md` is the protocol, `rake eval:classifier CASCADE=1`
# takes the reading and `rake eval:classifier_compare` gives the verdict. That
# rule is written here because it was broken here: the `also_named` and
# per-action target sentences shipped as an EARLIER revision of themselves, the
# text of the arm three loop iterations before the scored one, and nothing
# caught it because nothing was comparing them. The fixture and the test are
# what now do.
#
# A plausible-sounding prompt fix has more than once been measured moving the
# wrong number, which is why the rule is a rule and not a preference.
#
# THE ONE DELIBERATE EDIT IN THIS SHIP is `examine`, which now says "or looking
# around the place in general". It said only "something", an object, while a
# targetless look at the room is an `examine` in the corpus's own labels -- and
# the SAME words go into `Playthrough::Classifier::INSTRUCTIONS`, because two
# readers with two definitions of `examine` would make the escalation itself a
# source of disagreement, which is the one thing a cascade must not add.
class Playthrough::Classifier::Request
  NOTHING = Playthrough::IntentSchema::NOTHING
  TEXTS = EngineData.fetch("playthrough/classifier/request")

  INTENT_INSTRUCTIONS = TEXTS.fetch("intent_instructions")

  INTENT_CRITERIA = TEXTS.fetch("intent_criteria")

  # THE HALF OF EVERY TARGET QUESTION THAT IS THE SAME, and it is one string
  # rather than seven copies for the reason the closed set is one table: seven
  # copies of a matching rule drift, and the drift would be invisible because
  # each question is answered alone.
  #
  # "`also_named` handles another" is LOAD-BEARING and was measured missing: the
  # first drafting of the per-action questions dropped it, and 11 lines were lost
  # to collective phrasings with no single record to point at -- about the size
  # of the whole gap to the incumbent.
  #
  # AND THE COLLECTIVE WORDS ARE NAMED RATHER THAN IMPLIED, for the same reason
  # one iteration further on: told only that several fitting records may be
  # named, the reader answered `nothing` to `take everything on that shelf` and
  # its like. Naming the words, the `and then` continuation, and saying never
  # `nothing` where fitting records are listed is what recovered those lines --
  # and `also_named` below carries the matching sentence so the two questions
  # describe the same set. Neither sentence is a paraphrase of the other's
  # intent; they are the strings that were sent.
  TARGET_INSTRUCTIONS = format(TEXTS.fetch("target_instructions"), nothing: NOTHING).freeze

  # THE PREMISE EACH TARGET QUESTION IS ASKED UNDER, and the answer it gives when
  # the list holds nothing the line asked for. Speculative by design: every one
  # of these is answered whatever the intent turns out to be, and the engine
  # reads exactly one of them.
  Target = Data.define(:premise, :nothing)

  TARGETS = TEXTS.fetch("targets").to_h do |action, target|
    [ action.to_sym, Target.new(premise: target.fetch("premise"), nothing: target.fetch("nothing")) ]
  end.freeze

  ALSO_NAMED_INSTRUCTIONS = format(TEXTS.fetch("also_named_instructions"), nothing: NOTHING).freeze

  ALSO_NAMED_NOTHING = TEXTS.fetch("also_named_nothing")

  NAMED_MORE_THAN_ONE_INSTRUCTIONS = TEXTS.fetch("named_more_than_one_instructions")

  NAMED_MORE_THAN_ONE_CRITERIA = TEXTS.fetch("named_more_than_one_criteria")

  # WHY THIS QUESTION IS ASKED AT ALL, and it is the flag that carries the
  # cascade. Every reader measured here answers a line reaching for something
  # ABSENT by handing back the nearest present record instead -- "ask my landlord
  # for another week" in a room holding one person resolves to that person. This
  # asks the one thing that catches it, in isolation from which action it is:
  # is the thing the line asks for on any list at all?
  TARGET_PRESENT_INSTRUCTIONS = TEXTS.fetch("target_present_instructions")

  TARGET_PRESENT_CRITERIA = TEXTS.fetch("target_present_criteria")

  attr_reader :state

  def initialize(state)
    @state = state
  end

  # THE ID OF THE TARGET QUESTION ONE ACTION'S ANSWER IS READ FROM. One
  # definition, because the builder below and the composition that reads the
  # answer back must agree about it exactly.
  def self.target_id(action) = "target_#{action}"

  # The whole map, in the order the questions are listed above. A hash, keyed by
  # the ids the answers come back under; the ids are not sent to the model.
  def to_h
    questions = { "intent" => intent_question }
    TARGETS.each_key do |action|
      question = target_question(action)
      questions[self.class.target_id(action)] = question if question
    end
    also_named = also_named_question
    questions["also_named"] = also_named if also_named
    questions["named_more_than_one"] = { "type" => "noul", "instructions" => NAMED_MORE_THAN_ONE_INSTRUCTIONS,
                                         "criteria" => NAMED_MORE_THAN_ONE_CRITERIA }
    questions["target_present"] = { "type" => "noul", "instructions" => TARGET_PRESENT_INSTRUCTIONS,
                                    "criteria" => TARGET_PRESENT_CRITERIA }
    questions
  end

  private

  def intent_question
    { "type" => "choice", "instructions" => INTENT_INSTRUCTIONS, "criteria" => INTENT_CRITERIA }
  end

  # Nil for an action with no records here, which is how it is left unsent.
  def target_question(action)
    keys = state.keys_for(action)
    return nil if keys.empty?

    target = TARGETS.fetch(action)
    {
      "type" => "choice",
      "instructions" => "Assume, for this question only, that the player is #{target.premise}. #{TARGET_INSTRUCTIONS}",
      "criteria" => criteria_for(keys).merge(NOTHING => target.nothing)
    }
  end

  # EVERY RECORD IN THE POSITION AND NOT ONE INTENT'S SET, because the second
  # name a line carries is named before anybody has decided what the line is.
  # Narrowing it to the chosen intent's own records is the ENGINE's job, once the
  # intent is known -- see `Playthrough::Classifier::Cascade`.
  def also_named_question
    keys = state.all_keys
    return nil if keys.empty?

    {
      "type" => "choice",
      "instructions" => ALSO_NAMED_INSTRUCTIONS,
      "criteria" => criteria_for(keys).merge(NOTHING => ALSO_NAMED_NOTHING)
    }
  end

  # A criterion per option, and it is the record's own name. The key is what the
  # answer comes back as and what the engine resolves; the description is what
  # the model reads.
  def criteria_for(keys)
    keys.to_h { |key| [ key, state.label_for(state.record_for(key)) ] }
  end
end
