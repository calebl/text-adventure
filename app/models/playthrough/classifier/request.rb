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
# THE WORDING IS MEASURED TEXT. Every sentence below was sent, repeatedly, and
# scored on the hand-labelled corpus; `EVALUATION.md` is the protocol and
# `rake eval:classifier_compare` is the verdict. Do not improve a sentence here
# without a stored baseline either side of the edit -- a plausible-sounding
# prompt fix has more than once been measured moving the wrong number.
#
# THE ONE DELIBERATE EDIT IN THIS SHIP is `examine`, which now says "or looking
# around the place in general". It said only "something", an object, while a
# targetless look at the room is an `examine` in the corpus's own labels -- and
# the SAME words go into `Playthrough::Classifier::INSTRUCTIONS`, because two
# readers with two definitions of `examine` would make the escalation itself a
# source of disagreement, which is the one thing a cascade must not add.
class Playthrough::Classifier::Request
  NOTHING = Playthrough::IntentSchema::NOTHING

  INTENT_INSTRUCTIONS =
    "Which single intent is the player requesting in `player_action`? Keep the requested " \
    "intent even when its target is absent from the corresponding state list.".freeze

  INTENT_CRITERIA = {
    "move" => "The player is trying to go somewhere else or cross a doorway, whether or not the destination is listed in `ways_out`.",
    "talk" => "The player is speaking to or asking somebody; threats without physical contact and asking for somebody's item are talk.",
    "examine" => "The player is looking at, inspecting, or reading something more closely without moving or taking it, or looking around the place in general.",
    "take" => "The player is trying to pick something up from where they are, whether or not it is listed in `available_items`.",
    "drop" => "The player is trying to put down, leave behind, or give up something they carry, whether or not it is listed in `player_items`.",
    "attack" => "The player is trying to physically hurt somebody; a spoken threat without contact is talk.",
    "use" => "The player is trying to consume or burn an item, offer a carried item, or open a barrier.",
    "other" => "The line requests none of the other listed actions, such as waiting, reflecting, or making an unrelated observation."
  }.freeze

  # THE HALF OF EVERY TARGET QUESTION THAT IS THE SAME, and it is one string
  # rather than seven copies for the reason the closed set is one table: seven
  # copies of a matching rule drift, and the drift would be invisible because
  # each question is answered alone.
  #
  # "When the line requests several fitting records, choose one of them;
  # `also_named` handles another" is LOAD-BEARING and was measured missing: the
  # first drafting of the per-action questions dropped it, and 11 lines were lost
  # to collective phrasings with no single record to point at -- about the size
  # of the whole gap to the incumbent.
  TARGET_INSTRUCTIONS =
    "Which single listed record are they aiming that at? Match direct names, listed aliases, " \
    "ordinary shortened references, direct address, and an unambiguous pronoun when context " \
    "identifies one record. When the line requests several fitting records, choose one of them; " \
    "`also_named` handles another. Choose `#{NOTHING}` when the record they are asking for is " \
    "absent from this list. Never substitute a merely related record for an absent one. Answer " \
    "this question on its own; do not decide whether this is what the player is actually doing.".freeze

  # THE PREMISE EACH TARGET QUESTION IS ASKED UNDER, and the answer it gives when
  # the list holds nothing the line asked for. Speculative by design: every one
  # of these is answered whatever the intent turns out to be, and the engine
  # reads exactly one of them.
  Target = Data.define(:premise, :nothing)

  TARGETS = {
    move: Target.new(premise: "crossing a doorway to another location",
                     nothing: "No listed way out is the one being crossed, or the requested destination is absent."),
    talk: Target.new(premise: "speaking to or asking somebody",
                     nothing: "No listed person is the one being spoken to, or the requested person is absent."),
    attack: Target.new(premise: "physically hurting somebody",
                       nothing: "No listed person is the one being struck, or the requested person is absent."),
    take: Target.new(premise: "picking something up from where they are",
                     nothing: "Nothing listed here is the thing being picked up, or the requested thing is absent."),
    drop: Target.new(premise: "putting down, leaving behind or giving up something they carry",
                     nothing: "Nothing carried is the thing being put down, or the requested thing is absent."),
    examine: Target.new(premise: "looking at, inspecting or reading something more closely",
                        nothing: "Nothing listed here or carried is the thing being looked at, or the requested thing is absent."),
    use: Target.new(premise: "consuming or burning an item, offering a carried item, or opening a barrier",
                    nothing: "No listed attempt matches the request in action, object, recipient and tool.")
  }.freeze

  ALSO_NAMED_INSTRUCTIONS =
    "Independently inspect `player_action` and the state. Does the same requested intent " \
    "explicitly name or unambiguously include at least two distinct records from that intent's " \
    "appropriate state list? If so, choose one listed record distinct from the likely main " \
    "target; for an ordinary two-record request, choose the other record rather than " \
    "`#{NOTHING}`. Words such as `both`, `all`, `everything`, `the lot`, `them`, or `both of " \
    "them` include the fitting records in the corresponding list. Choose `#{NOTHING}` when fewer " \
    "than two fitting records are requested. Objects, tools, and recipients already bound inside " \
    "one complete `physical_actions` attempt are not a second act.".freeze

  ALSO_NAMED_NOTHING =
    "No appropriate listed record is named, or the requested target is absent from the " \
    "appropriate list.".freeze

  NAMED_MORE_THAN_ONE_INSTRUCTIONS =
    "First identify the one requested intent. Return a high yes probability only when that same " \
    "intent requests at least two distinct eligible records: move counts `ways_out`; talk or " \
    "attack counts `other_characters`; take counts `available_items`; drop counts " \
    "`player_items`; examine counts either item list. A talk command that directly names two " \
    "present people counts both even when one is addressed and the other appears inside the " \
    "requested message. A record listed only for a different intent does not count. If the " \
    "intent is `other`, the answer is no. Collective words such as `both`, `all`, `everything`, " \
    "`the lot`, or `them` count only when context unambiguously selects at least two eligible " \
    "records. A single `physical_actions` attempt is one act even when it binds several parts.".freeze

  NAMED_MORE_THAN_ONE_CRITERIA = {
    "true" => "The same non-other requested intent explicitly names or unambiguously includes at least two distinct records from its eligible state list.",
    "false" => "The line has at most one eligible listed record for its requested intent, refers only to absent or differently eligible records, is other, or names parts already bound inside one complete physical action."
  }.freeze

  # WHY THIS QUESTION IS ASKED AT ALL, and it is the flag that carries the
  # cascade. Every reader measured here answers a line reaching for something
  # ABSENT by handing back the nearest present record instead -- "ask my landlord
  # for another week" in a room holding one person resolves to that person. This
  # asks the one thing that catches it, in isolation from which action it is:
  # is the thing the line asks for on any list at all?
  TARGET_PRESENT_INSTRUCTIONS =
    "Does the state actually list the thing or person `player_action` asks for? Answer yes when " \
    "a listed record IS that thing - by name, by a listed alias, by an ordinary shortened " \
    "reference, by direct address, or by an unambiguous pronoun - and yes when a collective word " \
    "such as `everything`, `all of it`, `the lot`, `them`, `both` or `each` covers listed " \
    "records. Answer no when the line asks for something the state does not list and only " \
    "similar or related records are present: the rest of a group whose other members are absent, " \
    "a role or relationship nobody listed holds, or a thing held inside, made by or stored in a " \
    "listed record. Judge only what is asked for against what is listed; do not decide which " \
    "action it is.".freeze

  TARGET_PRESENT_CRITERIA = {
    "true" => "A listed record is the very thing or person the line asks for, or a collective word covers listed records.",
    "false" => "What the line asks for is absent from the state and only similar, containing or related records are listed."
  }.freeze

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
