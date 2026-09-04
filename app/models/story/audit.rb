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
# 2a. RE-MEASURED IN `ta-eval-pipeline` AND STILL DEAD, on 264 freshly generated
#    turns this time, with the scene cast on record rather than inferred. 58 of
#    the 264 name a character the scene does not have in it -- a vocabulary scan
#    would raise 58 flags. Requiring a SPEECH VERB beside the name, which is the
#    one narrowing finding 2 did not have data for, leaves 3. All three are
#    "says nothing":
#
#      "Grenn watches you with narrowed eyes but says nothing"
#      "Ammon Brace watches, his jaw set, but says nothing"
#
#    Three flags, three false positives, no true positives. And the records are
#    not up to the check anyway: a `Scene::Narrator` turn records no cast at
#    all, so on those turns EVERY character reads as absent (ROADMAP, *nothing
#    records where a character stands*). There is still no person check.
#
# 3a. AND A NAME THE RECORDS HOLD IS NOT THE NAME THE PROSE WRITES, which
#    `ta-eval-pipeline` found by pointing the finished check at 132 whole-run
#    narrations and watching it flag nothing. `Item#name` is "Ward Office 12
#    daybook" and every one of those narrations wrote "daybook". A check that is
#    live and permanently silent is the failure mode finding 2 warns about, so
#    the names come from `Story::Audit::Prose.item_names` now -- the recorded
#    name and its last substantial word. The same helper supplies the rooms
#    `check_arrival` reads.
#
# 3b. AND A POSSESSIVE IS NOT CUSTODY. With the alias in place the possessive
#    grammar raised 8 flags across those 12 transcripts and 6 were the sentence
#    "your daybook lies open on your desk" about a daybook the records had
#    lying on that desk -- true, and not a contradiction. Grammar 2 is dropped
#    when the thing is in the room the player is standing in; see
#    `#check_items`. The two survivors say "under your hand" of a book on the
#    desk, which is the captain's own `ta-narrator-invents-exit` sighting.
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
# 4. AND THE RECORDS DID NOT SAY WHAT A TURN DID, which is why the largest
#    measured defect in the game was invisible to every check above. `scenes`
#    carried the raw line the player typed and where they ended up -- what the
#    world IS after a turn, never what the turn DID -- so a check reading a
#    narration against the state BEFORE it had nothing to read, and
#    `unrecorded_departure` was reduced to inferring movement by comparing two
#    location ids. On the 480-turn baseline of 2026-09-03 the prose on a
#    resolved `take` denied the pickup on 28 of 32 take turns and a `drop`
#    invented one on 4 of 32, and a person reading a whole run found it where
#    nine checks did not. `Scene#resolved_action` and `Scene#acted_on` are the
#    record; `take_denied` and `pickup_invented` are the first two checks that
#    read one. See `#check_take`.
#
# 5. AND A WHEREABOUTS RECORD DOES NOT REVIVE THE PERSON CHECK, which is the
#    thing `ta-character-whereabouts` was expected to change and measurement
#    says it does not. `characters.location_id` landed, so the records are
#    finally authoritative about presence -- the objection in 2a ("a
#    `Scene::Narrator` turn records no cast at all, so on those turns EVERY
#    character reads as absent") is gone, and the candidate set is now the
#    strongest possible one: only somebody the records positively place in
#    ANOTHER ROOM. Somebody nowhere is unjudgeable and is never a candidate.
#    Measured over all three corpora -- 248 passages, whereabouts taken from
#    the checked-in world files:
#
#      36 passages are judgeable at all (12 in `eval_corpus.json`, 0 in
#      `narration_corpus.json`, 24 in `whole_run_corpus.json`), and ONE of
#      those 36 even names the absent person. It is a true positive: a `move`
#      turn into The Long Hallway whose prose is the previous turn's office
#      narration, with "Halkett's gaze moves to the book" in a room the
#      records place him nowhere near. So the check has a demonstrated positive
#      case (bar point 3) and no false-positive rate to report (bar point 2),
#      because n = 1.
#
#    AND THE ZERO IS AN ARTIFACT OF WHERE THE SEED FILES PUT PEOPLE, which a
#    sensitivity run settles. Move one character one door -- Grenn Ollivar into
#    the boarding-house hallway instead of Room 3, which is where a landlord
#    plausibly is and is an authoring choice, not a defect -- and the same
#    corpora produce 41 flags on a name scan and 4 on the narrowest grammar
#    that still keeps a true positive (a speech verb in the sentence, negations
#    dropped). Two of those four are the same false positive, and it is
#    finding 2's: *"From somewhere below, Grenn's voice rises in a muffled,
#    irritated shout"* -- correct prose about somebody genuinely in another
#    room. The name scan adds *"Grenn keeps the front door bolted after the
#    tenth bell"* (habitual) and *"a narrow room on the third floor of Grenn's
#    boarding house"* (a PLACE whose name contains a person's).
#
#    A window-based grammar -- the name, then a presence verb within twenty
#    characters -- survives that run with no false positives, and it is not
#    shipped either: twenty is a constant with nothing behind it, the FP
#    sentences clear it by a few characters rather than by grammar, and it was
#    tuned against the corpus it was measured on. That is what `Eval::HELD_OUT`
#    exists to stop.
#
#    SO THERE IS STILL NO PERSON CHECK. What would settle it is a corpus of
#    turns from a world whose cast is spread across rooms, which is now
#    possible to generate for the first time -- presence is a record, so
#    `rake eval:run` can produce runs in which people are demonstrably
#    elsewhere. Until that exists, the gap stays covered from the other side by
#    `Playthrough::Drift`, and by the engine: `Character.present_in` is the
#    closed set `talk` resolves against, so the player cannot SPEAK to somebody
#    who is not there whatever the prose says about them.
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
  # `take_denied` and `pickup_invented` are the two that read a CHANGE rather
  # than a state, and they are here rather than in a bucket of their own
  # because what they prove is the same thing: the records say what the turn
  # did and the narration says otherwise. See `#check_take`.
  CONTRADICTIONS = %i[unreachable_transition item_not_held unrecorded_departure unrecorded_arrival
                      take_denied pickup_invented inscription_misquoted].freeze

  # THE PROSE BROKE A RULE THE APP STATES, provable from the row itself and one
  # record. Not a disagreement between two records -- a defect in the passage.
  # `Story::Audit::Prose` holds the reading and the measurement for both.
  DEFECTS = %i[truncated_prose third_person_protagonist].freeze

  # Not proof, and never reported as if it were: the player reached for
  # something the records do not have, immediately after reading this
  # narration. See Playthrough::Drift.
  DRIFTS = %i[reached_for_nothing].freeze

  # NOT A DEFECT AND NOT A DRIFT: the player named two things the records
  # really have, and a turn is one act, so the loop did one of them. Nothing
  # here is wrong -- the count exists to answer whether one act per line is a
  # limit worth lifting, which is a question about how people type rather than
  # a matter of opinion. See Playthrough::Overreach.
  LIMITS = %i[named_more_than_one].freeze

  # NOT A DEFECT AT ALL, and counted apart from everything above for that
  # reason: a stretch of turns on which the records show nothing happening. A
  # player examining four things in a row is enjoying themselves; the same four
  # turns with somebody standing in the room who never acts is the complaint
  # this exists to count. It is evidence about pacing, like drift is evidence
  # about invention, and it is never added to the contradictions.
  PACING = %i[still_run].freeze

  # A name shorter than this is not scanned for. Three letters match half the
  # dictionary, and a false positive costs more here than a miss.
  MIN_NAME_LENGTH = 4

  # HOW MANY TURNS OF NOTHING BEFORE IT IS WORTH SAYING SO, and the number was
  # measured rather than chosen. Over 54 real scenes, a run of this length or
  # longer with somebody in the room flags 2 turns and one of them is the turn
  # the captain marked `weak` with *"this has stretch on too long. Some kind of
  # action is needed or a conversation. Why is Halkett not doing anything?"*.
  # At 5 it flags nothing at all and misses his turn; at 3 it flags 5 and at 2
  # it flags 10, none of the extras labelled. **Four is the longest run that
  # still catches the one turn known to be a real complaint**, which is the
  # precision-first way to pick a threshold. Re-derive it, do not adjust it by
  # feel: `Story::Scoreboard::CorpusTest` recomputes that table from the frozen
  # corpus and fails if a different threshold becomes the right answer.
  STILL_RUN = 4

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

  # A PREPOSITION BETWEEN THE NAME AND THE PLAYER'S PERSON, which means the
  # sentence has already put the name somewhere: "under your hand WITH the stamp
  # beside it" is not a claim about the stamp. Only grammar 3 consults this --
  # it is the one that matches over a window rather than over a phrase.
  #
  # `in`, `on`, `at` and `under` are deliberately NOT here: they are how grammar
  # 3 reaches the person in the first place, and adding them would make the
  # guard eat its own match.
  ATTACHED_ELSEWHERE = /\b(?:with|beside|besides|behind|beneath|below|underneath|
                            near|atop|against|among|amongst|across|between|beyond|
                            alongside|from|inside|onto|over|past|through|around|
                            toward|towards)\b/xi

  # WHAT THE RECORDS SAY ABOUT ONE NARRATION, and the evidence for saying it.
  #
  # `evidence` is a hash printed as-is by the rake task. It is verbose on
  # purpose: a flag nobody can judge without opening a console is a flag that
  # gets ignored, and the whole point of this class is flags that can be
  # defended one at a time.
  Flag = Data.define(:code, :scene, :headline, :evidence) do
    def contradiction? = CONTRADICTIONS.include?(code)
    def defect? = DEFECTS.include?(code)
    def drift? = DRIFTS.include?(code)
    def limit? = LIMITS.include?(code)
    def pacing? = PACING.include?(code)

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

  # `scenes:` narrows the sweep to a subset of the story's turns, and exists
  # for one caller: `Eval::RunSet`, which audits a generated run and must not
  # count the world's own hand-authored opening arrival. That passage is
  # identical in every run of that world, so counting it adds a constant to
  # every denominator and measures the seed file rather than the game.
  #
  # The `previous_scene` chain deliberately still reaches outside the scope --
  # the first played turn follows the opening, and a check that compares a turn
  # with the one before it needs that turn even when it is not being scored.
  # See `#previous_of`.
  def initialize(story, scenes: nil)
    @story = story
    @scene_scope = scenes
  end

  # Every story in the database, oldest first, each with its audit -- the same
  # shape `Story::Doctor.all` has, for the same reason.
  def self.all(scope = Story.all)
    scope.order(:created_at, :id).map { |story| new(story) }
  end

  # Oldest first, so a report reads in the order the story was played.
  def scenes
    @scenes ||= (@scene_scope || story.scenes)
                     .includes(:location, :characters, :interactions, previous_scene: :location)
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

  def defects = flags.select(&:defect?)

  def drifts = flags.select(&:drift?)

  def limits = flags.select(&:limit?)

  def pacing = flags.select(&:pacing?)

  def scanned = scenes.size

  def clean? = flags.empty?

  # WHICH CHECKS THIS STORY CAN ACTUALLY ANSWER, which `Story::Scoreboard`
  # prints so an absent flag is never mistaken for a clean one. Every check
  # runs against a real story except one: a world whose protagonist was never
  # marked has no name for `third_person_protagonist` to look for, and
  # `Character::Generator` still never sets `is_protagonist` (see the ROADMAP),
  # so that is a real shape a database holds rather than a hypothetical.
  def available_checks
    all = CONTRADICTIONS + DEFECTS + DRIFTS + LIMITS + PACING

    story.protagonist ? all : all - %i[third_person_protagonist]
  end

  # HOW MANY PASSAGES THIS CHECK COULD HAVE FIRED ON -- its denominator, and it
  # is not always the scene count. A difference needs two terms, so a check
  # that compares a turn with the one before it cannot be run on the first one;
  # counting those in would report a rate lower than the check earned.
  # `Story::Scoreboard` sums this across a corpus rather than working it out
  # again, because a denominator worked out twice is a denominator that can
  # disagree with itself.
  def judgeable_for(code)
    return 0 unless available_checks.include?(code)

    case code
    when :unreachable_transition, :unrecorded_departure, :still_run
      scenes.count(&:follows_a_turn?)
    when :reached_for_nothing, :named_more_than_one
      scenes.count { |scene| scene.typed.present? }
    when :unrecorded_arrival
      # Every scene with prose in it, whether or not a turn came before. A
      # first turn can be narrated as an arrival somewhere else just as easily.
      scenes.count { |scene| scene.description.present? }
    when :truncated_prose
      # Two fields per turn are read, not one: see `#check_truncation`.
      scenes.size + scenes.sum { |scene| scene.interactions.size }
    when :take_denied
      # THE TURNS THAT MADE THIS TRANSITION, and nothing else. A check that
      # reads a change can only be run on a turn that made one, so its
      # denominator is the recorded takes -- counting every scene in would
      # report a rate the check never earned. See `Scene#took?`.
      scenes.count { |scene| scene.took? && scene.description.present? }
    when :pickup_invented
      scenes.count { |scene| scene.dropped? && scene.description.present? }
    when :inscription_misquoted
      # THE TURNS THAT TOUCHED A THING WITH WORDS ON RECORD, which is the whole
      # of what this can be run on: no record, nothing to compare a quotation
      # with. See `#check_inscription`.
      scenes.count { |scene| inscribed_subject(scene) && scene.description.present? }
    else
      scenes.size
    end
  end

  # THE CAPTAIN'S OWN VERDICTS ON THESE TURNS, keyed by the scene they judge.
  # Keyed by the record rather than by its id because `Story::Scoreboard` reads
  # this alongside a frozen corpus whose passages have no ids.
  def verdicts
    @verdicts ||= begin
      rows = Playthrough::Feedback.where(scene_id: scenes.map(&:id)).pluck(:scene_id, :verdict).to_h
      scenes.filter_map { |scene| [ scene, rows[scene.id] ] if rows.key?(scene.id) }.to_h
    end
  end

  # How many of each code, for a number that can be watched over time.
  def tally
    flags.group_by(&:code).transform_values(&:size)
  end

  def headline
    return "#{scanned} scenes, nothing to report" if clean?

    counts = { "contradiction" => contradictions, "defect" => defects,
               "drift" => drifts, "still turn" => pacing }

    "#{scanned} scenes: " + counts.map { |noun, found| "#{found.size} #{noun.pluralize(found.size)}" }.join(", ")
  end

  private

  def run
    return if defined?(@flags) && @flags

    @flags = []
    @unjudged = []

    scenes.each do |scene|
      check_transition(scene)
      check_items(scene)
      check_truncation(scene)
      check_third_person(scene)
      check_departure(scene)
      check_arrival(scene)
      check_take(scene)
      check_drop(scene)
      check_inscription(scene)
    end

    check_stillness
    check_drifts
    check_overreaches
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
      # WHAT THE PROSE WOULD CALL IT, not only what the records do. `Item#name`
      # is "Ward Office 12 daybook" and not one of 132 whole-run narrations
      # ever wrote that string -- every one of them wrote "daybook". Matching
      # the recorded name alone left this check live and permanently silent,
      # which reads as a clean result. See `Story::Audit::Prose.item_names`.
      names = Prose.item_names(item)
      next if names.empty?

      # A BARE POSSESSIVE IS OWNERSHIP, AND OWNERSHIP IS NOT CUSTODY. "Your
      # daybook lies open on your desk" is true of a daybook the records have
      # lying in this very room, and flagging it would be wrong. Measured: on
      # the 12 whole-run transcripts the possessive raised 8 flags against a
      # daybook lying in the player's own room and 6 of the 8 were exactly that
      # sentence. Requiring the thing to be somewhere the player is not leaves
      # the two real ones -- "lies open under your hand", of a book on the desk
      # -- and costs nothing on the pinned corpus, where every planted item is
      # in another room or another pair of hands.
      claim = names.find { |name| possession_claimed?(text, name, custody_only: item.location_id == scene.location_id) }
      next if claim.nil?

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
           "named as" => claim,
           "records say" => item.whereabouts,
           claim: excerpt(text, claim),
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
  #
  # `custody_only` drops grammar 2. See `#check_items` for the measurement that
  # forced it: with the thing lying in the room the player is standing in, "your
  # daybook" is a true sentence about a book on the desk.
  #
  # AND GRAMMAR 3 STOPS AT A PREPOSITION IN ONE DIRECTION ONLY, which was
  # forced by measurement and the asymmetry is the whole finding. It matches in
  # either order over a window, and on
  #
  #   "Your daybook lies open under your hand with the stamp beside it."
  #
  # the PERSON-FIRST order read "under your hand ... the stamp" and claimed the
  # player was holding a stamp the sentence puts beside the daybook. A
  # preposition standing between the person and the name has attached the name
  # to something else, so that window ends there.
  #
  # THE NAME-FIRST ORDER IS NOT GUARDED, and guarding it cost three defensible
  # flags on the pinned corpus, every one of the form
  #
  #   "You pull the compass FROM your satchel, its brass casing cool and heavy
  #    in your palm."
  #
  # There the prepositions describe where the thing came from and the sentence
  # still ends with it in the player's hand. Which is the difference: with the
  # name first it is the subject and the prepositions are its journey; with the
  # person first a preposition introduces a new noun phrase, and the name in it
  # is somebody else's business.
  def possession_claimed?(text, name, custody_only: false)
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
      #    pistol at your hip" and "in your hand, the pistol" -- but the span
      #    between the two must not cross a preposition, or the sentence has
      #    already attached the name to something else. See the note above.
      /\b#{word}\b[^.!?;:]{0,60}?\b(?:in|on|at|against|under)\s+your\s+(?:#{places})\b/i,
      /\b(?:in|on|at|against|under)\s+your\s+(?:#{places})\b(?<before_name>[^.!?;:]{0,60}?)\b#{word}\b/i
    ]
    patterns.delete_at(2) if custody_only

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
      # GRAMMAR 3, FORWARD ORDER ONLY: a preposition standing between the
      # player's person and the name has attached the name to something else.
      next if match.names.include?("before_name") && match[:before_name].to_s.match?(ATTACHED_ELSEWHERE)

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

  # Everything in the story that no player is holding. An item in somebody
  # else's hands or lying on a floor is the only kind that can be falsely
  # claimed; what the player really has needs no checking.
  #
  # WHAT "THE PLAYER" MEANS HERE IS EVERY PLAYTHROUGH OF THE STORY, and it has
  # to be, because a `Scene` carries no playthrough: the turn log is a
  # `previous_scene` chain read backwards from a playthrough, so there is no
  # column to join on. So this excludes the union of what any party carries,
  # plus the story's starting inventory, which is held by the protagonist and
  # copied into every party's hands. Precision over recall, which is this
  # class's rule everywhere: a name one player is genuinely holding is not
  # flagged in another player's turn.
  #
  # ONE PER NAME. Two items called "brass stamp" in two different places is a
  # real state, but a sentence that says "you put the brass stamp in your
  # pocket" names one thing -- so it earns one flag, not one per row. Reporting
  # both reads as a bug in the sweep, which is the same cost as a false
  # positive.
  def items_elsewhere
    @items_elsewhere ||= begin
      in_hand = Item.carried_by(story.playthroughs).pluck(:name) + story.starting_inventory.pluck(:name)
      in_hand = in_hand.map { |name| name.to_s.downcase.strip }.to_set

      Item.where(character: story.characters).or(Item.where(location: story.locations))
          .includes(:character, :location)
          .order(:id)
          .to_a
          .uniq { |item| item.name.to_s.downcase.strip }
          .reject { |item| in_hand.include?(item.name.to_s.downcase.strip) }
    end
  end

  # ------------------------------------------------------------------------
  # THE PASSAGE STOPS MID-SENTENCE.
  #
  # Two fields, because two things are cut off by the same failure and only one
  # of them is visible: `Scene#description` is what the player reads -- the
  # captain marked one `bad` with the single word *"truncated"* -- and
  # `Interaction#action` is the fact the talk narration is then written from,
  # so a severed one produces a severed turn a step later.
  #
  # The reading is `Story::Audit::Prose.truncated?` and the measurement is in
  # its header. Nothing here is judged against a cap: `SanitizesGeneratedText`
  # already refuses a field that arrives at its schema ceiling, and both real
  # `Interaction` rows in the corpus were cut off well under theirs.
  # ------------------------------------------------------------------------
  def check_truncation(scene)
    passages = [ [ "the narration the player read", "scenes.description", scene.description ] ]
    scene.interactions.sort_by(&:id).each do |interaction|
      passages << [ "what #{interaction.character&.fullname || "somebody"} did",
                    "interactions.action ##{interaction.id}", interaction.action ]
    end

    passages.each do |what, field, text|
      next if text.to_s.strip.empty?
      next unless Prose.truncated?(text)

      flag(:truncated_prose, scene,
           "#{what} stops mid-sentence",
           field: field,
           claim: "…#{text.to_s.rstrip.last(80)}",
           "last character" => Prose.sentence_ending(text).inspect,
           length: text.to_s.length,
           where: scene.location&.name)
    end
  end

  # ------------------------------------------------------------------------
  # THE NARRATION WROTE THE PROTAGONIST AS SOMEBODY ELSE.
  #
  # The captain's words: *"referring to Vance in the third person (instead of
  # using 'you')."* The failure is not cosmetic -- at its worst the narration
  # splits the player in two and puts their own character in the doorway
  # watching them arrive. Twelve flags across nine real narrations, and in every
  # one of the nine the protagonist is standing opposite the player.
  #
  # `Story::Audit::Prose.third_person_references` is the reading, the three
  # grammars it accepts and the one guard that makes it defensible are
  # documented there, and the protagonist's names come from the records rather
  # than from the prose.
  #
  # A STORY WITH NO PROTAGONIST CANNOT BE CHECKED, and says so rather than
  # passing. `Character::Generator` still never sets `is_protagonist` (see the
  # ROADMAP), so a generated world reaches this with nobody to look for, and a
  # silent pass would read as a clean result.
  # ------------------------------------------------------------------------
  def check_third_person(scene)
    text = scene.description.to_s
    return if text.blank?

    if protagonist_names.empty?
      return unjudge(:third_person_protagonist, scene,
                     "this story has no protagonist on record, so there is no name to check the narration against")
    end

    Prose.third_person_references(text, protagonist_names).each do |reference|
      flag(:third_person_protagonist, scene,
           "the narration writes #{reference.name.inspect} as a third person, and that is the player " \
           "(#{story.protagonist.fullname}), who is only ever \"you\"",
           grammar: reference.kind,
           name: reference.name,
           claim: reference.sentence.truncate(220),
           "the player is" => story.protagonist.fullname,
           where: scene.location&.name)
    end
  end

  def protagonist_names
    @protagonist_names ||= Prose.protagonist_names(story.protagonist)
  end

  # ------------------------------------------------------------------------
  # A DOOR CLOSED AT THE PLAYER'S BACK AND THE PLAYER DID NOT GO ANYWHERE.
  #
  # The captain's words: *"the narration says a door clicked behind me but I'm
  # still in the Ward Office 12."* This is `check_transition`'s question asked
  # from the other side. There, two scenes name two places and the graph either
  # joins them or does not. Here the prose asserts a departure and the records
  # say the location never changed -- which the app owns outright, because
  # `Playthrough::Turn#move_to` is the only thing that changes it.
  #
  # The prose half is `Story::Audit::Prose.departure_claims` and its ordering
  # rule is what keeps it honest. The record half is exact, and the corpus
  # proves the pair discriminates rather than the pattern alone: three real
  # narrations close a door behind the player and two of them really did move,
  # so only the third is flagged.
  # ------------------------------------------------------------------------
  def check_departure(scene)
    previous = scene.previous_scene
    return if previous.nil?
    return if left_the_room?(scene, previous)

    Prose.departure_claims(scene.description).each do |claim|
      flag(:unrecorded_departure, scene,
           "the narration closes a door behind the player, and the records have them still in " \
           "#{scene.location&.name.inspect}",
           claim: claim.truncate(220),
           "records say" => "still in #{scene.location&.name}",
           "previous scene" => "##{previous.id} (#{previous.location&.name})",
           typed: scene.typed.presence)
    end
  end

  # WHETHER THE PLAYER LEFT THIS ROOM ON THIS TURN -- read off the record where
  # there is one, inferred from the two location ids where there is not.
  #
  # `Scene#moved_to?` is the record, and it is exact: `Playthrough::Turn#move_to`
  # is the only thing in the app that moves anybody, and it now writes down that
  # it did. Comparing the ids is what this check had before that column existed,
  # and it is an inference with a hole that matters here -- a move whose
  # destination is the room it started from reads as staying put, so a door
  # closing at the player's back would be flagged on a turn they really did walk
  # through. Nothing seeds a loop edge today; `Location::Generator` writing one
  # is a change away, and this check should not be what discovers it.
  #
  # A turn that recorded an action which is NOT a move did not move, whatever
  # the ids say. A turn with no action on record falls back to the ids, which is
  # every turn played before the column existed and is why no pinned count
  # moves: on all of them the two answers are the same.
  def left_the_room?(scene, previous)
    return scene.moved_to? if scene.recorded_action.present?

    previous.location_id != scene.location_id
  end

  # ------------------------------------------------------------------------
  # THE NARRATION WALKED THE PLAYER INTO A ROOM BY NAME, AND THE RECORDS HAVE
  # THEM SOMEWHERE ELSE.
  #
  # `check_departure` is this from behind -- a door closing at the player's
  # back with no destination named -- and both answer the captain's
  # `ta-narrator-invents-exit`: *"the narrator asserts state changes the game
  # never records."* They are separate checks because they read different
  # sentences: one has a threshold and no place, this one has a place and no
  # threshold, and a passage can do either without doing the other.
  #
  # THE RECORD IS EXACT AND THE PROSE IS THE ONLY LOOSE HALF, which is the
  # shape every check here wants. `Playthrough::Turn#move_to` is the only thing
  # that changes `Scene#location`, so where the player is at the end of this
  # turn is not in question; the question is only whether the narration said
  # somewhere else. `Story::Audit::Prose.arrival_claims` is the reading and its
  # measurement -- 224 real passages, 8 detections, 0 false positives -- is in
  # its header.
  #
  # WHAT IT CANNOT SEE, and it is the same gap the whole sweep has: a room the
  # story does not have. The names come from the records, so prose that invents
  # a wine cellar out of nothing matches nothing here. That is
  # `Playthrough::Drift`'s half of the work.
  # ------------------------------------------------------------------------
  def check_arrival(scene)
    return if scene.description.blank?
    return if scene.location.nil?

    Prose.arrival_claims(scene.description, place_names.keys).each do |arrival|
      claimed = place_names.fetch(arrival.name)
      # ARRIVING WHERE YOU ARE IS WHAT A `move` TURN NARRATES, and is correct.
      #
      # THIS HALF NEEDED NO RECORD, which is worth saying next to
      # `#left_the_room?`, where the same question did. `Scene#location` IS the
      # destination on a move turn -- `Playthrough::Turn#move_to` writes both --
      # so where the player ended up was never inferred here, only where they
      # came from was, and this check does not ask that.
      next if claimed == scene.location.name

      flag(:unrecorded_arrival, scene,
           "the narration walks the player into #{claimed.inspect}, " \
           "and the records have them in #{scene.location.name.inspect}",
           claim: arrival.sentence.truncate(220),
           "named as" => arrival.name,
           "records say" => "in #{scene.location.name}",
           typed: scene.typed.presence,
           at: scene.story_timestamp)
    end
  end

  # EVERY PLACE THIS STORY HAS, by every name the prose might use it under,
  # mapped back to the one the records hold. Built once per sweep: a story's
  # locations do not change under it.
  #
  # A NAME TWO PLACES ANSWER TO IS DROPPED, not guessed at. A world with both
  # "Grenn's Boarding House hallway" and "The Long Hallway" has two rooms whose
  # alias is "hallway", and a flag that cannot say which one it means is a flag
  # nobody can judge.
  def place_names
    @place_names ||= begin
      claimed = Hash.new(0)
      story.locations.each { |place| Prose.place_names(place.name).each { |name| claimed[name.downcase] += 1 } }

      story.locations.flat_map { |place| Prose.place_names(place.name).map { |name| [ name, place.name ] } }
           .reject { |name, _| claimed[name.downcase] > 1 }
           .to_h
    end
  end

  # ------------------------------------------------------------------------
  # THE PROSE DENIES THE PICKUP THE APP JUST MADE.
  #
  # THE FIRST CHECK HERE THAT READS A CHANGE RATHER THAN A STATE, and it is
  # what `Scene#resolved_action` and `Scene#acted_on` were added for. Every
  # other check reads one scene against the world as it stands: the records
  # carry what the world IS after a turn and never carried what the turn DID,
  # so the largest measured defect in the game was invisible to all nine of
  # them. On the 480-turn baseline of 2026-09-03 the narration denied the
  # pickup on 28 of 32 turns the app had already recorded as a `take`, and it
  # took a person reading a whole run for twenty minutes to find that.
  #
  # THE RECORD IS EXACT AND THE PROSE IS THE ONLY LOOSE HALF, which is the
  # shape every check here wants. `Playthrough::Turn#take_item` moves the row
  # out of the closed set the classifier resolved against and BEFORE any prose
  # exists, so a scene that answers `Scene#took?` is a scene on which the item
  # was demonstrably not the player's a moment earlier -- the state before the
  # turn, read off the transition itself rather than inferred from a
  # neighbouring row. `Playthrough::Turn#taken_fact` then hands the narrator
  # that sentence in the app's own words. This counts how often it is ignored.
  #
  # `Story::Audit::Prose.prior_possession_claims` is the reading, its two
  # grammars and its stated miss are documented there, and the measurement --
  # zero flags on all three existing corpora, six detections on the twelve
  # recorded takes of `whole_run_corpus.json` -- is in
  # `Story::Audit::TransitionTest`.
  # ------------------------------------------------------------------------
  def check_take(scene)
    return if scene.description.blank?
    return unless scene.took?

    item = scene.acted_on
    claim = Prose.prior_possession_claims(scene.description, Prose.item_names(item)).first
    return if claim.nil?

    flag(:take_denied, scene,
         "this turn picked the #{item.name} up, and the narration tells the player they already had it",
         item: item.name,
         "named as" => claim.name,
         "the turn did" => "take #{item.name}",
         "so before it" => "the #{item.name} was lying in #{scene.location&.name || "this room"}, not held",
         claim: claim.sentence.truncate(220),
         typed: scene.typed.presence,
         where: scene.location&.name,
         at: scene.story_timestamp)
  end

  # ------------------------------------------------------------------------
  # THE PROSE PICKS UP WHAT THE TURN PUT DOWN.
  #
  # `check_take` from the other end, and the same guarantee behind it:
  # `Playthrough::Turn#drop_item` moves the row out of the closed set of what
  # the records say the player is carrying, so a scene that answers
  # `Scene#dropped?` is a scene on which the item WAS in the player's hands a
  # moment earlier. Prose that lifts it off a floor or a wall first has
  # invented a pickup, and the next turn's records disagree with the paragraph
  # the player just read.
  #
  # SEPARATE FROM `take_denied` AND NEVER MERGED WITH IT, on the rule the whole
  # sweep works to: they read different sentences, they miss different things,
  # and one number for both would say less than either. On the baseline this
  # fires on 4 of 32 recorded drops where the other fires on 28 of 32.
  #
  # `Story::Audit::Prose.invented_pickup_claims` is the reading and its stated
  # miss -- prose that writes "the slate" of an "Assize tide-slate" -- is in
  # its header.
  # ------------------------------------------------------------------------
  def check_drop(scene)
    return if scene.description.blank?
    return unless scene.dropped?

    item = scene.acted_on
    claim = Prose.invented_pickup_claims(scene.description, Prose.item_names(item)).first
    return if claim.nil?

    flag(:pickup_invented, scene,
         "this turn put the #{item.name} down, and the narration has the player pick it up first",
         item: item.name,
         "named as" => claim.name,
         "the turn did" => "drop #{item.name}",
         "so before it" => "the #{item.name} was in the player's hands, not lying anywhere",
         claim: claim.sentence.truncate(220),
         typed: scene.typed.presence,
         where: scene.location&.name,
         at: scene.story_timestamp)
  end

  # ------------------------------------------------------------------------
  # THE PROSE QUOTES A NOTE AND THE NOTE SAYS SOMETHING ELSE.
  #
  # THE COMPLAINT IT ANSWERS is the captain's, and it is the whole reason
  # `items.inscription` exists. Playthrough 15, scene 77: he typed *"pickup the
  # note. what does it say?"* and read back *"Midnight. The Bell. They know
  # about the maps."* -- invented on the spot, kept nowhere, and free to be
  # something different the next time he unfolded it. The words are a record
  # now; this is the check that reads a passage against it.
  #
  # WHAT IT READS is a CHANGE-shaped fact in the same sense `take_denied` is:
  # the item this turn acted on is known exactly (`Scene#acted_on`), and what is
  # written on it is a column the narrator was handed verbatim
  # (`Playthrough::Turn#read_fact`). So a quotation in the prose is comparable
  # with something rather than with an impression.
  #
  # IT IS NOT SCOPED TO A READ, and that is deliberate rather than loose. The
  # turn that produced the complaint was a `take`: the player picked the note up
  # and asked what it said in one line, and the loop recorded a take. A
  # quotation of written text contradicts the record whichever verb the turn
  # resolved to, and scoping this to `examine` would have excluded the one turn
  # it was built for.
  #
  # PRECISION, MEASURED. `Story::Audit::Prose.inscription_quotes` is the reading
  # half and its numbers are on the method: over all 367 real passages in the
  # four corpora, 92 hold a double-quoted span and 177 spans in total -- nearly
  # every one of them dialogue -- and the cue rule raises ZERO of them. The
  # positive case is the captain's own narration above, with the record put
  # under it; `Story::Audit::InscriptionTest` pins both.
  #
  # WHAT IT KNOWINGLY MISSES, and it is most of the recall:
  #
  #   * prose that says what a note says WITHOUT quoting it -- "the note names a
  #     time and a place" is unjudgeable, and a paraphrase that contradicts the
  #     record reads exactly like one that agrees with it.
  #   * prose that quotes with `says` -- "the note says 'Midnight'". `says` is
  #     the commonest speech attribution in the corpus and putting it on the cue
  #     list flagged seven passages of dialogue and nothing else. The item's own
  #     name in place of a cue was measured too and raised three flags, all
  #     dialogue.
  #   * MOST REAL READS, AS THINGS STAND. Three live narrations of a read, two
  #     of them quoting the recorded words in quote marks, and this detected
  #     neither: both set the quotation on its own line after a paragraph break,
  #     with no cue near it. The check is nearly silent on well-behaved prose,
  #     and that is a stated cost rather than a discovered one -- what it catches
  #     is the shape that produced the complaint, prose that announces text as
  #     written and then writes different text.
  #   * a thing nobody has written the words down for. A readable item with no
  #     inscription has no record to disagree with, so the turn is not counted
  #     in the denominator either -- see `#judgeable_for`.
  # ------------------------------------------------------------------------
  def check_inscription(scene)
    return if scene.description.blank?

    item = inscribed_subject(scene)
    return if item.nil?

    Prose.inscription_quotes(scene.description).each do |quote|
      next if Prose.same_written_words?(quote.text, item.inscription)

      flag(:inscription_misquoted, scene,
           "the narration quotes what is written on the #{item.name}, and the records hold different words",
           item: item.name,
           "the records say" => item.inscription.to_s.truncate(220),
           "the narration says" => quote.text.truncate(220),
           claim: quote.sentence.truncate(220),
           typed: scene.typed.presence,
           where: scene.location&.name,
           at: scene.story_timestamp)
    end
  end

  # THE THING THIS TURN ACTED ON, when it is a thing with words on record. Both
  # halves are needed and neither is enough: a turn with no `acted_on` acted on
  # nothing nameable, and a readable item nobody has read yet holds no words for
  # a quotation to disagree with.
  def inscribed_subject(scene)
    item = scene.acted_on_record
    return nil unless item.is_a?(Item) && item.inscribed?

    item
  end

  # ------------------------------------------------------------------------
  # A STRETCH OF TURNS ON WHICH THE RECORDS SHOW NOTHING HAPPENING.
  #
  # The captain's words: *"this has stretch on too long. Some kind of action is
  # needed or a conversation. Why is Halkett not doing anything?"* Both halves
  # of that are records, and neither is prose: a turn is STILL when the player
  # did not move, no `Interaction` was written and no `WorldEvent` fell in the
  # interval -- which is every record a turn can leave -- and the run is what
  # the complaint is actually about. One quiet turn is a game; four in a row
  # with somebody standing there is the thing he stopped to write about.
  #
  # SOMEBODY HAS TO BE IN THE ROOM, and that is the second half of his sentence
  # rather than a refinement of the first. It is read HISTORICALLY -- who was in
  # the room on that turn, not who is there now -- because the complaint is
  # about the turn. Every turn carries that answer on it now
  # (`Playthrough::Turn#play` snapshots `Character.present_in` onto every
  # branch); a turn played before it did falls back to the old rule, whoever was
  # in the last scene here that recorded anyone. See `#cast_recorded_by`.
  #
  # THIS IS NOT A DEFECT AND IT IS NOT COUNTED AS ONE. Nothing here proves the
  # turn was bad; a player reading a daybook for four turns is playing the game
  # as designed. It is a pacing measurement, in the `PACING` bucket, and the
  # threshold that decides it is `STILL_RUN` -- see that constant for how the
  # number was arrived at and what it costs.
  #
  # WHAT IT CANNOT SEE: a `take` or a `drop`. Both move a real row and neither
  # leaves anything dated on the turn -- `Item` carries only a wall-clock
  # `updated_at` -- so a turn that picked something up reads as still. That is a
  # gap in the records rather than in the check, and it closes when
  # `ta-item-registry` gives an item a history.
  # ------------------------------------------------------------------------
  def check_stillness
    scenes.each do |scene|
      next if still_run_length(scene) != STILL_RUN

      present = cast_recorded_by(scene)
      next if present.empty?

      flag(:still_run, scene,
           "#{STILL_RUN} turns running, the records show nothing changed, and " \
           "#{present.map(&:fullname).join(", ")} #{present.one? ? "is" : "are"} in the room",
           run: "#{STILL_RUN} turns with no move, no conversation and no world event",
           present: present.map(&:fullname).join(", "),
           typed: scene.typed.presence,
           where: scene.location&.name,
           at: scene.story_timestamp)
    end
  end

  # How many turns of nothing this scene sits at the end of, walked back along
  # `previous_scene` -- the chain one player actually played -- rather than
  # along story time, which interleaves every playthrough of the world.
  #
  # ONLY THE TURN THAT REACHES THE THRESHOLD IS FLAGGED (`== STILL_RUN`, not
  # `>=`), so a ten-turn stretch is one flag rather than seven. A count that
  # grows with the length of the thing it is measuring makes the tally
  # unreadable.
  def still_run_length(scene, seen = Set.new)
    @still_runs ||= {}
    return @still_runs[scene.id] if @still_runs.key?(scene.id)
    return 0 unless seen.add?(scene.id)

    previous = previous_of(scene)
    @still_runs[scene.id] =
      if previous.nil? || !still?(scene, previous)
        0
      else
        still_run_length(previous, seen) + 1
      end
  end

  # The previous scene AS THIS SWEEP ALREADY LOADED IT, so walking a chain of
  # 500 turns costs no queries and reads the same preloaded interactions the
  # rest of the run does. Falls back to the association for a scene whose
  # predecessor belongs to another story, which nothing writes and the records
  # do not forbid.
  def previous_of(scene)
    return nil if scene.previous_scene_id.nil?

    scenes_by_id.fetch(scene.previous_scene_id) { scene.previous_scene }
  end

  def scenes_by_id = @scenes_by_id ||= scenes.index_by(&:id)

  def still?(scene, previous)
    return false if previous.location_id != scene.location_id
    return false if scene.interactions.any?
    return false if scene.story_timestamp.nil? || previous.story_timestamp.nil?

    world_event_times.none? { |at| at > previous.story_timestamp && at <= scene.story_timestamp }
  end

  def world_event_times
    @world_event_times ||= story.world_events.pluck(:occurred_at).compact
  end

  # Whoever the game believed was standing here at this moment: the cast of the
  # last scene in this location, at or before this one, that recorded anybody.
  # The protagonist is dropped -- they are the player, and a player is never the
  # answer to "who is in the room with me".
  def cast_recorded_by(scene)
    # THE TURN'S OWN SNAPSHOT FIRST, because since `ta-character-whereabouts` it
    # has one: `Playthrough::Turn#play` writes the room's cast onto every branch
    # out of `Character.present_in`, so the exact answer for this turn is on
    # this turn. It used to be written only by an arrival and a talk -- 184 of
    # the 480 baseline turns had none -- which is why the scan below exists and
    # why it stays: a turn played before the snapshot did still has to be judged
    # the way it would have been judged then, and re-reading history under a new
    # rule would move a measured number without anything about the game having
    # changed.
    return scene.characters.to_a - [ story.protagonist ].compact if scene.characters.any?

    candidates = scenes.select do |other|
      other.location_id == scene.location_id && other.characters.any? &&
        (other.story_timestamp.nil? || scene.story_timestamp.nil? ||
         other.story_timestamp <= scene.story_timestamp)
    end

    (candidates.last&.characters.to_a - [ story.protagonist ].compact)
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

  # ------------------------------------------------------------------------
  # A LINE THAT NAMED TWO THINGS, AND THE ONE THE TURN DID NOT DO. Not a
  # defect: both names resolved and the turn acted on one, because one line is
  # one act. Reported so the limit is a number rather than an impression. See
  # Playthrough::Overreach.
  # ------------------------------------------------------------------------
  def check_overreaches
    Playthrough::Overreach.for_story(story).in_story_order.includes(:scene, :location).each do |overreach|
      flag(:named_more_than_one, overreach.scene,
           "the player typed #{overreach.command.to_s.strip.inspect}, which named two things the records have, " \
           "and the turn could only #{overreach.action} one of them",
           action: overreach.action,
           typed: overreach.command,
           "acted on" => overreach.acted,
           "left undone" => overreach.unacted,
           where: overreach.location&.name,
           at: overreach.story_timestamp)
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
