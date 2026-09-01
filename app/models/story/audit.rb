# WHAT THE NARRATOR SAID, AGAINST WHAT THE WORLD ACTUALLY RECORDS.
#
# Offline, deterministic, and free: no model call, no API key, no network, no
# per-turn cost. It reads stored `Scene`s and the records around them and says
# where the prose and the database disagree. `rake game:audit` runs it.
#
# WHY IT EXISTS. The standing constraint (AGENTS.md) is that nothing may depend
# on the narrator obeying its prompt: *gate the state, inform the prose, audit
# the difference.* This is the third clause. It cannot make the narrator behave
# and it does not try to -- it turns "the narration drifts sometimes" into a
# number, so the cost of doing something about it can be weighed against a
# measurement instead of an impression.
#
# PRECISION IS THE DESIGN GOAL, NOT RECALL, and every check here was kept or
# cut against a measurement rather than against how useful it sounded. The
# corpus is 24 real narrations from two remote models over six commands
# designed to break a world's laws, checked in at
# `test/fixtures/files/narration_corpus.json` and pinned by
# `Story::AuditPrecisionTest`. Three findings, in the order they arrived:
#
# 1. A VOCABULARY SCAN CANNOT WORK, and it is gone. The first version of this,
#    built as a spike, asked "which names the records know appear in this
#    prose". It raised four flags on the 24 and all four were false positives:
#    "Mournwell Lane" is visible through the room's window and the seeded
#    description says so; "The Ever-Shifting Bazaar" was named by the player's
#    own command. MENTIONING A THING IS NOT CLAIMING YOU CAN REACH IT. Prose
#    refers to places through windows, people in memory and objects in shop
#    fronts. There is no `place_not_reachable` here and there must not be one.
#
# 2. NEITHER CAN A NAME SCAN FOR PEOPLE, which the spike had expected to keep,
#    on the reasoning that naming a person does imply they are here. It does
#    not. Of the six narrations in the corpus that name the absent landlord,
#    two put him in the room ("Grenn's broad frame fills the doorway"), two put
#    him audibly downstairs ("Grenn's voice comes creaking up the stairwell"),
#    one is habitual ("Grenn keeps the front door bolted after the tenth
#    bell") and one denies him outright ("Grenn does not come"). No pattern
#    separates those. Requiring a QUOTATION attributed to the name looked like
#    the way out, and measurement killed it too: every quotation in the corpus
#    is attributed by pronoun -- "he says", "He mutters" -- so the check would
#    have been a check that never fires, which is worse than no check because
#    it reads as a clean result. So there is no person check. That gap is
#    covered from the other side, and exactly, by `Playthrough::Drift`.
#
# 3. POSSESSION IS DIFFERENT, and it is the one place prose is read. "You draw
#    your revolver" is not a mention: it is a sentence about a record, in the
#    grammar of a claim -- the player as subject of a possession verb, or the
#    item marked as theirs, or the item on their person. Measured on the corpus
#    with items planted under the names the prose argues about: 8 flags, 8 true
#    positives, ZERO false positives, against 15 narrations that name one of
#    those items. A vocabulary scan would have flagged all 15. Recall is the
#    price: roughly half the real possession claims are missed, because prose
#    says "wrench the revolver free" and no closed verb list has every verb.
#
# WHAT IT CANNOT DO, stated so nobody expects it to: deterministic verification
# catches the MISUSE of things that exist. It cannot catch the INVENTION of
# things that do not, because you cannot scan prose for a name you were never
# given. That gap is `Playthrough::Drift`, which measures inventions by their
# consequences -- the player walking at a door that is not there -- and is
# reported here as drift, counted separately from the contradictions the
# records prove outright.
#
# AND A CHECK THAT CANNOT BE RUN HONESTLY IS RECORDED AS UNJUDGED rather than
# guessed at. A shuffled graph, a scene with no story time, an item whose row
# changed after the scene was written: all unjudgeable, and saying so is the
# difference between an instrument and an opinion.
class Story::Audit
  # A DISAGREEMENT THE RECORDS PROVE. Every one of these is a defect in the
  # game, not a matter of taste about the prose.
  CONTRADICTIONS = %i[unreachable_transition item_not_held].freeze

  # Not proof, and never reported as if it were: the player reached for
  # something the records do not have, immediately after reading this
  # narration. See Playthrough::Drift.
  DRIFTS = %i[reached_for_nothing].freeze

  # A name shorter than this is not scanned for. Three letters match half the
  # dictionary, and a false positive costs more here than a miss.
  MIN_NAME_LENGTH = 4

  # Verbs that put a thing in the player's hands.
  POSSESSION_VERBS = %w[
    have hold holds holding held carry carries carrying
    take takes taking took pick picks picked pocket pockets pocketed
    draw draws drew grip grips gripped clutch clutches clutching
    wield wields lift lifts lifted
  ].freeze

  # Where a thing sits when it is the player's. Body parts and what they are
  # wearing, and nothing that is merely nearby -- "on your desk" is not
  # possession, which is why `desk` and `table` are absent.
  ON_THE_PERSON = %w[
    hand hands palm palms fist fingers grip arm arms shoulder shoulders
    hip hips belt waist pocket pockets coat jacket satchel bag pack
    holster back chest neck lap
  ].freeze

  # Any of these in the sentence a match sits in and the match is dropped:
  # "there is no revolver, no pistol, no weapon of any kind on your person"
  # reads exactly like a possession claim to a regex and is the opposite of one.
  NEGATIONS = /\b(?:no|not|never|without|nothing|neither|n't|lack|lacks|lacked|
                   empty|unarmed)\b/xi

  # WHAT THE RECORDS SAY ABOUT ONE NARRATION, and the evidence for saying it.
  #
  # `evidence` is a hash printed as-is by the rake task. It is verbose on
  # purpose: a flag nobody can judge without opening a console is a flag that
  # gets ignored, and the whole point of this class is flags that can be
  # defended one at a time.
  Flag = Data.define(:code, :scene, :headline, :evidence) do
    def contradiction? = CONTRADICTIONS.include?(code)
    def drift? = DRIFTS.include?(code)

    # The one line of evidence worth putting next to the headline where there is
    # only room for one -- a table column, a summary. Different per check,
    # because what convicts an item claim is the sentence and what convicts a
    # transition is the exit list.
    def evidence_line
      return evidence[:claim] if evidence[:claim].present?

      exits = evidence.find { |key, _| key.to_s.start_with?("exits from") }
      return "#{exits.first}: #{exits.last}" if exits

      evidence[:typed].presence
    end
  end

  # A CHECK THAT WAS NOT RUN, because running it would have meant guessing.
  # Counted and reported: the coverage is part of the reading.
  Unjudged = Data.define(:code, :scene, :reason)

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Every story in the database, oldest first, each with its audit -- the same
  # shape `Story::Doctor.all` has, for the same reason.
  def self.all(scope = Story.all)
    scope.order(:created_at, :id).map { |story| new(story) }
  end

  # Oldest first, so a report reads in the order the story was played.
  def scenes
    @scenes ||= story.scenes
                     .includes(:location, :characters, previous_scene: :location)
                     .order(:story_timestamp, :id)
                     .to_a
  end

  def flags
    run
    @flags
  end

  def unjudged
    run
    @unjudged
  end

  def contradictions = flags.select(&:contradiction?)

  def drifts = flags.select(&:drift?)

  def scanned = scenes.size

  def clean? = flags.empty?

  # How many of each code, for a number that can be watched over time.
  def tally
    flags.group_by(&:code).transform_values(&:size)
  end

  def headline
    return "#{scanned} scenes, nothing to report" if clean?

    "#{scanned} scenes: #{contradictions.size} contradiction#{"s" unless contradictions.one?}, " \
      "#{drifts.size} drift#{"s" unless drifts.one?}"
  end

  private

  def run
    return if defined?(@flags) && @flags

    @flags = []
    @unjudged = []

    scenes.each do |scene|
      check_transition(scene)
      check_items(scene)
    end

    check_drifts
    @flags
  end

  # ------------------------------------------------------------------------
  # THE PLAYER ENDED UP SOMEWHERE THE GRAPH FORBIDS.
  #
  # No text scanning at all, and that is why it is first: two consecutive
  # scenes name two locations, and either there is a `LocationConnection`
  # between them or there is not. Exact, and the check the vocabulary scan was
  # replaced by -- the app owns movement, so the question is not which names
  # appear in the prose but whether the state change matches the graph.
  #
  # `Playthrough::Classifier` resolves a move out of the room's real exits, so
  # the play path cannot produce this. What can: a scene placed by hand (a
  # script, a fixture, a harness), and a bug in a future branch that moves the
  # player some other way. Both are worth knowing about.
  # ------------------------------------------------------------------------
  def check_transition(scene)
    previous = scene.previous_scene
    return if previous.nil?
    return if previous.location_id == scene.location_id

    if scene.story_timestamp.nil? || previous.story_timestamp.nil?
      return unjudge(:unreachable_transition, scene,
                     "a scene with no story time cannot be placed against the world's events")
    end

    # THE GRAPH READ HERE IS TODAY'S GRAPH. `WorldMechanic::ShuffleConnections`
    # repoints edges on the story's clock, so an edge that existed when the
    # player walked it may be gone now -- and a sweep that called that a
    # violation would be reporting the world working as designed. If anything
    # moved either end since, the check cannot be run honestly.
    if graph_moved_since?(previous, scene)
      return unjudge(:unreachable_transition, scene,
                     "the world moved one of these places after this turn, so the edge walked cannot be read back")
    end

    out = LocationConnection.find_by(location: previous.location, connected_location: scene.location)
    return if out

    back = LocationConnection.find_by(location: scene.location, connected_location: previous.location)

    flag(:unreachable_transition, scene,
         "the player got from #{previous.location.name.inspect} to #{scene.location.name.inspect} " \
         "with no edge between them",
         from: previous.location.name,
         to: scene.location.name,
         "edge out" => "missing",
         "edge back" => back ? "present (a one-way edge -- see Story::Doctor)" : "missing",
         "exits from #{previous.location.name}" => previous.location.exits.pluck(:name).sort.join(", ").presence || "none",
         at: scene.story_timestamp)
  end

  # Any world event touching either end at or after the earlier scene. The
  # bound is deliberately generous: a shuffle after the fact rewrites the graph
  # this check reads, whether or not it happened during the move itself.
  def graph_moved_since?(previous, scene)
    story.world_events
         .where(occurred_at: previous.story_timestamp..)
         .joins(:locations)
         .where(locations: { id: [ previous.location_id, scene.location_id ] })
         .exists?
  end

  # ------------------------------------------------------------------------
  # THE NARRATION TOLD THE PLAYER THEY ARE CARRYING SOMETHING THEY ARE NOT.
  #
  # This is the check app-owned `take` makes worth having. Taking is now a row
  # the app writes out of a closed set (`Playthrough::Turn#take_item`), so
  # `Item#character` is the only answer to "does the player have it" -- and a
  # narration that hands the player something the records give to somebody else
  # is measurably wrong rather than arguably wrong.
  #
  # The pattern needs the PLAYER and a POSSESSION VERB and the item's name in
  # one sentence, with no negation in the span. "There is no revolver, no
  # pistol, no weapon of any kind on your person" is a refusal, reads to a
  # regex exactly like a possession claim, and is dropped by the negation
  # guard -- that sentence is a real narration from the corpus this was
  # measured against.
  # ------------------------------------------------------------------------
  def check_items(scene)
    text = scene.description.to_s
    return if text.blank?
    return if items_elsewhere.empty?

    items_elsewhere.each do |item|
      next if item.name.to_s.strip.length < MIN_NAME_LENGTH
      next unless possession_claimed?(text, item.name)

      # THE ROW MAY HAVE MOVED SINCE. Ownership is not dated in story time, so
      # a row touched after this scene was written cannot be read back to it --
      # an item the player held then and gave away later would otherwise be
      # flagged for a narration that was correct when it was written.
      if scene.created_at && item.updated_at > scene.created_at
        next unjudge(:item_not_held, scene,
                     "#{item.name.inspect} changed hands after this scene was written, so who held it then is unknown")
      end

      flag(:item_not_held, scene,
           "the player is told they have the #{item.name}, which the records say is #{item.whereabouts}",
           item: item.name,
           "records say" => item.whereabouts,
           claim: excerpt(text, item.name),
           where: scene.location&.name)
    end
  end

  # THREE GRAMMARS OF A POSSESSION CLAIM, and nothing outside them. Each one is
  # the narration saying the thing is the player's or in the player's hands --
  # which is a claim about a record. A mention is not: "the ledger lies open on
  # the table" and "she reads from the daybook" say nothing about what the
  # player has, and neither matches.
  #
  #   1. the player, a possession verb, the name: "you draw your revolver"
  #   2. the name marked as the player's: "your daybook", "the daybook of yours"
  #   3. the name located on the player's person: "the pistol at your hip",
  #      "the compass heavy in your palm"
  #
  # All three then pass the negation guard, which is what keeps a refusal from
  # reading as a claim. Measured against 24 real narrations: see the header.
  def possession_claimed?(text, name)
    verbs = Regexp.union(POSSESSION_VERBS)
    places = Regexp.union(ON_THE_PERSON)
    word = Regexp.escape(name)

    patterns = [
      # 1. The player is the subject of a possession verb aimed at the name,
      #    in one sentence, in either order.
      /\b(?:you|your)\b[^.!?;:]{0,60}?\b#{verbs}\b[^.!?;:]{0,60}?\b#{word}\b/i,
      /\b#{word}\b[^.!?;:]{0,40}?\byou(?:r|'re| are)?\b[^.!?;:]{0,20}?\b#{verbs}\b/i,
      # 2. "your revolver" -- the possessive is the claim, and up to two words
      #    of adjective are allowed between ("your Nocturna-infused pistol").
      /\byour\b(?:\s+[\w'’-]+){0,2}\s+#{word}\b/i,
      # 3. On the player's person. Either order, because prose says both "the
      #    pistol at your hip" and "in your hand, the pistol".
      /\b#{word}\b[^.!?;:]{0,60}?\b(?:in|on|at|against|under)\s+your\s+(?:#{places})\b/i,
      /\b(?:in|on|at|against|under)\s+your\s+(?:#{places})\b[^.!?;:]{0,60}?\b#{word}\b/i
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      next if match.nil?
      # A NEGATION ANYWHERE IN THE SENTENCE turns the claim into its opposite,
      # and noticing that is most of what makes this defensible. The window is
      # the whole sentence rather than the matched span, and that was a
      # correction forced by a measurement: with only the span guarded,
      #
      #   "You reach for the revolver at your hip, but your fingers find only
      #    the empty holster."
      #
      # was flagged as a possession claim. The denial is in the clause AFTER
      # the match. Widening the guard to the sentence costs one true positive
      # on the corpus -- a narration that says "the pistol at your hip" and
      # then, of somebody else, "does not flinch" -- and that trade is taken on
      # purpose. A flag nobody can defend is worth less than a miss.
      next if sentence_around(text, match).match?(NEGATIONS)

      return true
    end

    false
  end

  # The sentence the match sits in. Ends are the nearest sentence terminator on
  # either side, so the guard reads what the narration actually said about the
  # thing rather than the fragment a regex happened to bite off.
  def sentence_around(text, match)
    before = text[0...match.begin(0)].to_s
    after = text[match.end(0)..].to_s

    start = before.rindex(/[.!?]\s/)
    finish = after.index(/[.!?](?:\s|\z)/)

    text[(start ? start + 1 : 0)..(match.end(0) + (finish || after.length))].to_s
  end

  # Everything in the story that the protagonist is not holding. An item in
  # somebody else's hands or lying on a floor is the only kind that can be
  # falsely claimed; what the player really has needs no checking.
  #
  # ONE PER NAME. Two items called "brass stamp" in two different places is a
  # real state, but a sentence that says "you put the brass stamp in your
  # pocket" names one thing -- so it earns one flag, not one per row. Reporting
  # both reads as a bug in the sweep, which is the same cost as a false
  # positive.
  def items_elsewhere
    @items_elsewhere ||= begin
      held = story.protagonist ? Item.for_character(story.protagonist) : Item.none
      Item.where(character: story.characters).or(Item.where(location: story.locations))
          .where.not(id: held.select(:id))
          .includes(:character, :location)
          .order(:id)
          .to_a
          .uniq { |item| item.name.to_s.downcase.strip }
    end
  end

  # ------------------------------------------------------------------------
  # DRIFT, MEASURED BY ITS CONSEQUENCES. One row per turn on which the player
  # reached for something the closed sets do not have, reported against the
  # narration they had just read. See Playthrough::Drift for why this is
  # evidence rather than proof.
  # ------------------------------------------------------------------------
  def check_drifts
    Playthrough::Drift.for_story(story).in_story_order.includes(:scene, :location).each do |drift|
      flag(:reached_for_nothing, drift.scene,
           "after this narration the player tried to #{drift.action} #{drift.command.to_s.strip.inspect}, " \
           "and the records had nothing of that name",
           action: drift.action,
           typed: drift.command,
           "was offered" => drift.offered.presence || "nothing at all",
           where: drift.location&.name,
           at: drift.story_timestamp)
    end
  end

  # The sentence the match was found in, trimmed, so a flag can be judged
  # without opening the scene.
  def excerpt(text, name)
    sentences = text.split(/(?<=[.!?])\s+/)
    hit = sentences.find { |sentence| sentence.match?(/\b#{Regexp.escape(name)}\b/i) }
    return text.truncate(160) if hit.nil?

    hit.strip.truncate(220)
  end

  def flag(code, scene, headline, **evidence)
    @flags << Flag.new(code: code, scene: scene, headline: headline, evidence: evidence)
  end

  def unjudge(code, scene, reason)
    @unjudged << Unjudged.new(code: code, scene: scene, reason: reason)
    nil
  end
end
