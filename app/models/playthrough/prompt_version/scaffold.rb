# THE PER-TURN SCAFFOLD, RENDERED ONCE AGAINST FIXED PLACEHOLDERS, SO A DIGEST
# CAN COVER IT.
#
# WHAT THE SCAFFOLD IS. A narrated turn's prompt is not one block of text: it is
# `Scene::Narrator::INSTRUCTIONS` as the system message, and then a user message
# the app builds out of `Scene::Narrator#prompt_for` -- the framing of a `fact:`
# and the `DOING` line -- wrapped around whatever `Playthrough::Turn` wrote as
# that fact (`#taken_fact`, `#dropped_fact`, `#thrown_fact`, `#read_fact`,
# `#written_words_fact`). Every one of those sentences is an INSTRUCTION in
# every meaningful sense: "Narrate it as done. Do not contradict it and do not
# undo it." is the app telling the narrator how to write, and changing it
# changes the prose exactly the way changing the instruction block does.
#
# WHY IT WAS NOT COVERED, AND WHAT CHANGED. `Playthrough::PromptVersion` read
# the instruction text back off the stored conversation, and the scaffold cannot
# be read back that way -- it arrives interleaved with the facts and no reader of
# one stored user message can tell one from the other. That is a true statement
# about a STORED PROMPT and it was taken, wrongly, as a reason the scaffold could
# not be versioned at all. It can: the scaffold is CODE, and code can be rendered
# against fixed inputs and digested. That is what this class does, and it is the
# same thing `Eval::Prompt::Version`'s `prompt_digest` does from the other side --
# except that one needs a corpus, a database and a paid run, and this needs
# nothing.
#
# TEXT THE MODEL ACTUALLY RECEIVES, and never method source. A digest of source
# would move on a rename, a comment, an extracted helper -- refactors that change
# no prompt -- and a version that cries wolf is a version nobody reads. So every
# branch is RENDERED and the rendered strings are what is digested: change a word
# of the wording and the digest moves; move the same words into a new method and
# it does not.
#
# EVERY BRANCH, ON PURPOSE. A conditional clause is wording too -- the ` -- ` in
# front of an item's description, the sentence a fumble adds when the thing is
# still in your hands -- so each conditional is rendered both ways. A branch this
# misses is a wording change the digest would sleep through, which is the exact
# defect this class exists to close.
#
# WHAT IS STILL NOT COVERED, stated so nobody reads more into a matching digest
# than it can carry: the rest of `Playthrough::Moment#narration_context`'s own
# framing -- its `Handled` note IS rendered here, because it is a fixed sentence
# about a change of possession and belongs with the fact that names the same
# row, but the surrounding lines are built together with the live records they
# state and rendering them needs a database -- and `Scene::Generator`'s arrival
# prompt. Both are covered by `Eval::Prompt::Version#prompt_digest`, which is a
# fingerprint of everything and the reason that digest exists.
class Playthrough::PromptVersion::Scaffold
  # PLACEHOLDERS, AND THEY ARE ANGLE-BRACKETED FOR A REASON: no prompt in this
  # app writes a `<` , so a rendered scaffold cannot be mistaken for a real
  # prompt by a person reading a diff, and no placeholder can be confused with
  # the wording around it. They are fixed for ever -- changing one moves the
  # digest for no prompt change, which is the one thing this class must not do.
  FACTS = "<the moment, from the records>".freeze
  COMMAND = "<what the player typed>".freeze
  FACT = "<what the app already did>".freeze
  WORDS = "<what is written on it>".freeze

  # THE THINGS THE SENTENCES ARE ABOUT, as the narrowest stand-ins that answer
  # what the fact builders ask them. Not `Item` and `Character` rows, because
  # this has to render with no database at all: `Playthrough::PromptVersion
  # .narration` is read by a test, a board and a doc, and none of them should
  # need one.
  Thing = Struct.new(:name, :description, :inscription, :bulk, :carried, keyword_init: true) do
    def inscribed? = inscription.present?
    def carried? = carried
  end

  Person = Struct.new(:fullname)
  Place = Struct.new(:name)

  PLAIN = Thing.new(name: "<item>", bulk: "handy", carried: true).freeze
  DESCRIBED = Thing.new(name: "<item>", description: "<its description>",
                        inscription: WORDS, bulk: "heavy", carried: false).freeze
  SOMEBODY = Person.new("<who>").freeze
  SOMEWHERE = Place.new("<where>").freeze

  # THE WHOLE SCAFFOLD AS ONE STRING, in a fixed order, under the same NUL
  # separator `Playthrough::PromptVersion::JOINER` uses and for its reason: two
  # adjacent sentences must not run together into a third string that neither of
  # them is.
  JOINER = Playthrough::PromptVersion::JOINER

  def self.text = new.text

  def text = (framings + facts).join(JOINER)

  private

  # `Scene::Narrator#prompt_for` WITH THE FACTS STOOD OUT. Every shape of user
  # message the narrator is ever handed: with a fact and without one, and one per
  # `DOING` key, because that line is wording keyed on the intent.
  def framings
    narrator = Narration.new(FACTS)

    [ narrator.framing(COMMAND, nil, nil), narrator.framing(COMMAND, FACT, nil) ] +
      Scene::Narrator::DOING.keys.map { |intent| narrator.framing(COMMAND, FACT, intent) }
  end

  # `Playthrough::Turn`'S FACT SENTENCES, every branch of every one of them --
  # including the optional third argument each of the take and drop sentences
  # gained with `ta-take-drop-narration`, since where a thing came from and who
  # put it down are two more clauses of wording.
  def facts
    turn = Facts.new

    [ turn.taken(PLAIN, SOMEBODY, nil),
      turn.taken(DESCRIBED, SOMEBODY, SOMEWHERE),
      turn.dropped(PLAIN, SOMEWHERE, nil),
      turn.dropped(DESCRIBED, SOMEWHERE, SOMEBODY),
      turn.read(PLAIN, WORDS),
      turn.written_words(PLAIN, WORDS) ] + thrown(turn) + handled_notes
  end

  # AND THE MARK THE MOVED ROW CARRIES IN THE STANDING LISTS
  # (`Playthrough::Moment::Handled#note`), which is the other half of the same
  # sentence: the fact says what the turn did and this says which line of the
  # list it did it to. It is wording, it is fixed, and it renders with no
  # record, so it is here rather than left to the bench.
  def handled_notes
    %i[taken dropped].map { |direction| Playthrough::Moment::Handled.new(item: PLAIN, direction: direction).note }
  end

  # ONE PER OUTCOME, AND TWO FOR A FUMBLE, which says something different about
  # where the thing ended up depending on whether it was ever in your hands.
  def thrown(turn)
    outcomes = [
      Playthrough::Turn::Throw.new(kind: :fumbled, item: PLAIN, target: SOMEBODY),
      Playthrough::Turn::Throw.new(kind: :fumbled, item: DESCRIBED, target: SOMEBODY),
      Playthrough::Turn::Throw.new(kind: :struck, item: PLAIN, target: SOMEBODY),
      Playthrough::Turn::Throw.new(kind: :thrown, item: PLAIN, target: SOMEWHERE),
      Playthrough::Turn::Throw.new(kind: :immovable, item: DESCRIBED, target: SOMEBODY)
    ]

    outcomes.map { |outcome| turn.thrown(outcome, SOMEBODY) } +
      [ turn.thrown(outcomes.first, nil) ]
  end

  # THE TWO SEAMS INTO THE CLASSES THAT OWN THE WORDING, and they are subclasses
  # rather than copies for the only reason that matters here: a copy would go
  # stale the first time somebody edited the real one, and a digest of a stale
  # copy is worse than no digest. Both builders are private, and both are pure
  # functions of their arguments -- they read no record and no ivar -- which is
  # what makes rendering them offline honest rather than a trick.
  class Narration < Scene::Narrator
    def initialize(context) = @context = context

    def framing(command, fact, intent) = send(:prompt_for, command, fact, intent)

    private

    # THE ONE THING STOOD OUT, and the argument is swallowed on purpose: what
    # `handled` changes is a line of the MOMENT, which is not rendered here, and
    # the optional parameter keeps this working whichever way that signature
    # goes next.
    def context(_handled = nil) = @context
  end

  class Facts < Playthrough::Turn
    def initialize = nil

    def taken(item, taker, from) = send(:taken_fact, item, taker, from)
    def dropped(item, here, dropper) = send(:dropped_fact, item, here, dropper)
    def thrown(outcome, thrower) = send(:thrown_fact, outcome, thrower)
    def read(item, words) = send(:read_fact, item, words)
    def written_words(item, words) = send(:written_words_fact, item, words)
  end
end
