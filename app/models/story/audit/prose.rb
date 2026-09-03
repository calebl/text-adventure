# WHAT CAN BE READ OUT OF A PASSAGE ALONE, with no database behind them.
#
# Every predicate here is pure: text in, a boolean or a list of matches out.
# That is deliberate and it is what makes the checks measurable. `Story::Audit`
# supplies the records that turn a match into a flag -- the protagonist's real
# name, whether the player actually moved -- and `Story::Scoreboard::Corpus`
# supplies the same facts from a checked-in file, so the SAME code reads the
# live database and the frozen corpus and the two cannot drift apart.
#
# WHY THESE AND NOT OTHERS. They are the errors the captain noticed
# unaided while playing, in his own words: prose that stops mid-sentence, the
# protagonist written as somebody standing opposite him, and a door closing at
# his back in a room he never left, and -- added by `ta-eval-pipeline`, from
# the same complaint as the door -- the narration walking him into a room by
# name that the records never moved him to. Nothing here was invented because
# it sounded checkable. See `Story::Audit`'s header for the prose heuristics
# this project has already measured and killed.
#
# PRECISION, MEASURED. Against 92 real passages -- 54 stored `Scene`
# descriptions, 14 `Interaction` actions and the 24 narrations in
# `narration_corpus.json` -- the first three raise 17 flags and every one of
# them is a true positive, with zero flags on the 24 narrations from the lab
# sweep. `Story::Scoreboard::CorpusTest` pins that, one flag at a time.
# `arrival_claims` was measured the same way over a wider set -- those 92 plus
# the 132 whole-run narrations of the four-arm lab sweep -- and its numbers are
# on the method. The recall is worse than the precision on purpose, and each
# method says where it knowingly misses.
module Story::Audit::Prose
  extend self

  # ------------------------------------------------------------------------
  # THE PASSAGE STOPS MID-SENTENCE.
  #
  # A provider that cuts a response off leaves a fragment, and a fragment is
  # not a shorter answer -- it is an answer whose end is missing. The app
  # already refuses one at the seam it can see it (`SanitizesGeneratedText`
  # raises when a field arrives at its schema cap) but the narrator's prose has
  # no cap to land on, so the only evidence left is the last character.
  #
  # THE RULE IS THE LAST CHARACTER AND NOTHING ELSE: after trailing whitespace
  # and any closing quotes, brackets or emphasis marks are removed, narration
  # ends on `.`, `!`, `?` or an ellipsis. Measured over 92 real passages: 88 end
  # on one of those four, 4 do not, and all 4 are genuinely cut off mid-word or
  # mid-clause ("...set in the careful, unsmudg").
  #
  # SCOPED TO WHAT THE PLAYER READS, which is `Scene#description` and
  # `Interaction#action`. It must not be pointed at `Character#likes` or
  # `Interaction#pre_feeling`: those are comma-separated lists that legitimately
  # end on a word, and running this over every prose column in the database
  # turned up 40 such fields. A check aimed at the wrong fields is not a
  # stricter check, it is a broken one.
  # ------------------------------------------------------------------------

  # Marks that legitimately sit AFTER the full stop: dialogue closes on a
  # quote, an aside on a bracket, an emphasised sentence on an asterisk.
  CLOSING_MARKS = [ '"', "'", "”", "’", "*", "_", ")", "]", "»", "›" ].freeze

  # What the end of a finished sentence looks like. An em-dash is deliberately
  # absent -- see `truncated?`.
  TERMINATORS = %w[. ! ? …].freeze

  def truncated?(text)
    ending = sentence_ending(text)
    return false if ending.nil?

    # A DASH IS NOT JUDGED EITHER WAY, and that is a decision rather than an
    # oversight: "But I never—" is a real way for an interrupted line to end
    # and so is a passage the provider severed at a dash. Nothing in the 92
    # passages measured ends on one, so there is no evidence to choose with,
    # and guessing would put an unmeasured flag next to three measured ones.
    return false if ending.match?(/[-—–]/)

    TERMINATORS.exclude?(ending)
  end

  # The last character that decides the question: trailing whitespace and
  # closing marks stripped. Nil for a passage with nothing in it.
  def sentence_ending(text)
    trimmed = text.to_s.rstrip.sub(/[#{Regexp.escape(CLOSING_MARKS.join)}\s]+\z/, "")

    trimmed.empty? ? nil : trimmed[-1]
  end

  # ------------------------------------------------------------------------
  # THE PROTAGONIST IS WRITTEN AS SOMEBODY ELSE.
  #
  # `Scene::Narrator::INSTRUCTIONS` requires the second person, and this is the
  # failure that breaks the game rather than merely the prose: the narration
  # stops addressing the player and starts describing a character with their
  # name standing opposite them. Twelve flags across nine real narrations, and
  # in every one of the nine the protagonist has become an NPC the player is
  # talking to.
  #
  # A MENTION IS NOT A VIOLATION, and that is the whole difficulty. This
  # project has already measured what happens when prose is scanned for a name
  # it knows (`Story::Audit`, finding 2): nothing separates a name that is a
  # claim from a name that is furniture. So the name alone is never enough
  # here. THREE GRAMMARS ARE, each of them the name being used as a third
  # person rather than being used as a word:
  #
  #   1. POSSESSIVE       "Isbet's lips thin" -- in the second person the
  #                       protagonist's things are always "your" things.
  #   2. SENTENCE SUBJECT the sentence opens on the name: "Isbet Marrow does
  #                       not wave back."
  #   3. COREFERENCE      the name, then a third-person pronoun later in the
  #                       same sentence: "the sight of Isbet Marrow exactly
  #                       where you left her".
  #
  # AND ONE GUARD, which is what makes it defensible: A NAME INSIDE QUOTATION
  # MARKS IS SOMEBODY ADDRESSING THE PLAYER, which is correct and wanted.
  # Without it, `"...your choice, Miss Marrow." He turns and thumps back down
  # the stairs` -- a real narration from the corpus, and a good one -- reads as
  # a violation, because the landlord's "He" follows the player's own name.
  # That was the only false positive the three rules produced on 92 passages
  # and the guard removes it.
  #
  # WHAT IT MISSES, stated because a silent miss is worse than a stated one:
  # an apposition with no pronoun and no possessive. "a figure -- Isbet Marrow
  # -- watches you" is a violation this does not catch, and catching it needs
  # to know that "watches" is a verb, which is a part-of-speech tagger and not
  # a regex. One miss in nine real violations; the trade is the same one
  # `Story::Audit` takes everywhere.
  # ------------------------------------------------------------------------

  # Third-person pronouns, which is what the protagonist must never be given.
  PRONOUNS = /\b(?:he|she|they|him|her|his|hers|their|theirs|himself|herself|themselves)\b/i

  # Speech, in both the straight and the curly convention. A name in here is
  # somebody talking to the player, not the narrator forgetting who they are.
  QUOTED = /"[^"]*"|“[^”]*”/

  # One place the narration used the protagonist's name as a third person.
  Reference = Data.define(:kind, :name, :sentence)

  # Every third-person reference to `names` in `text`. `names` is the
  # protagonist's names as the records hold them -- see `.protagonist_names`.
  def third_person_references(text, names)
    body = text.to_s
    return [] if body.blank? || names.empty?

    spans = quoted_spans(body)
    found = []

    each_sentence(body) do |sentence, at|
      names.each do |name|
        sentence.scan(/\b#{Regexp.escape(name)}(['’]s)?\b/i) do
          match = Regexp.last_match
          next if spans.any? { |span| span.cover?(at + match.begin(0)) }

          kind = reference_kind(sentence, match)
          found << Reference.new(kind: kind, name: name, sentence: sentence.strip) if kind
        end
      end
    end

    # ONE PER SENTENCE PER GRAMMAR. "Isbet's mouth tightens, and she doesn't
    # look at you" is possessive AND coreference AND sentence-initial, and
    # reporting it three times reads as a bug in the sweep -- which costs the
    # same as a false positive. See `Story::Audit#items_elsewhere` for the same
    # rule applied to items.
    found.uniq { |reference| [ reference.kind, reference.sentence ] }
  end

  # THE NAMES A CHARACTER CAN BE CALLED, as the records hold them: the full
  # name, the nickname, and each part of the full name on its own, because
  # narration says "Isbet" and "Marrow" as readily as "Isbet Marrow".
  #
  # `Story::Audit::MIN_NAME_LENGTH` applies for the same reason it applies to
  # items: three letters match half the dictionary.
  def protagonist_names(character) = character_names(character)

  # The same derivation for anybody, which is what `Eval::Richness` needs to ask
  # whether a narration named the person standing in the room. Takes a
  # `Character` or the string a fixture holds instead of one.
  def character_names(character)
    return [] if character.nil?

    parts =
      if character.respond_to?(:fullname)
        [ character.fullname, character.nickname ] + character.fullname.to_s.split(/\s+/)
      else
        [ character.to_s ] + character.to_s.split(/\s+/)
      end

    parts.map { |name| name.to_s.gsub(/[^\w'’-]/, " ").strip }
         .reject { |name| name.length < Story::Audit::MIN_NAME_LENGTH }
         .uniq
  end

  # ------------------------------------------------------------------------
  # A DOOR CLOSES AT THE PLAYER'S BACK IN A ROOM THEY NEVER LEFT.
  #
  # The captain's words: *"the narration says a door clicked behind me but I'm
  # still in the Ward Office 12."* Half of this is prose and half is a record,
  # and the record is the half that convicts: the app owns movement, so
  # `Scene#location_id` against the previous scene's is exact. This method
  # supplies only the prose half.
  #
  # THE ORDER OF THE THREE PARTS IS THE RULE, not their presence: a threshold,
  # then a verb that closes it, then "behind you", in that sequence in one
  # sentence. That is the grammar of "the door clicks shut behind you" and it
  # is what separates it from "behind you, close enough to touch, the narrow
  # door of the supply closet stands exactly as unlocked as it has stood for
  # eleven years" -- a real opening narration, which contains a threshold, the
  # word "close" and "behind you", and asserts nothing at all. Requiring the
  # order drops it; requiring only the words keeps it.
  #
  # "behind your" is not "behind you": the corpus has fog behind a brow, a
  # pressure behind the eyes and a stamp on a desk behind you, and the word
  # boundary excludes the first two while the ordering excludes the third.
  # ------------------------------------------------------------------------

  # A thing you go through. Nouns only -- a "passage" or an "exit" is a place
  # in this game's vocabulary, not a door, and would drag the map into a prose
  # check.
  THRESHOLD = /\b(?:door|doorway|gate|gateway|hatch|curtain|archway|shutter|portal|trapdoor)\b/i

  # Verbs that close one. `close` on its own is absent and `closes`/`closed`
  # are present, because the bare form is an adjective at least as often as it
  # is a verb -- "close enough to touch" is what taught that.
  CLOSING = /\b(?:clicks?|clicked|shuts?|closes|closed|closing|swings?|swung|slams?|slammed|
                 latches?|latched|seals?|sealed|bangs?|banged|thuds?|thudded)\b/xi

  # Every sentence that closes a threshold at the player's back.
  def departure_claims(text)
    body = text.to_s
    return [] if body.blank?

    sentences(body).select do |sentence|
      threshold = sentence.match(THRESHOLD)
      next false if threshold.nil?

      closing = sentence.match(CLOSING, threshold.end(0))
      next false if closing.nil?

      sentence.match?(/\bbehind you\b/i, closing.end(0))
    end.map(&:strip)
  end

  # ------------------------------------------------------------------------
  # THE PROSE WALKED THE PLAYER SOMEWHERE THE RECORDS DID NOT MOVE THEM.
  #
  # `departure_claims` above is the same defect caught from behind -- a door
  # closing at the player's back, with no destination named. This is the front:
  # the narration says where the player went, by name, and the records say they
  # are somewhere else. Both belong to `ta-narrator-invents-exit`, "the narrator
  # asserts state changes the game never records"; they are separate checks
  # because they read different sentences and miss different things.
  #
  # THE NAME COMES FROM THE RECORDS, never from the prose. That is the line
  # `Story::Audit`'s header draws and this stays on the right side of it: the
  # app cannot scan for a place it was never told about, so a wholly invented
  # room is invisible here and is measured by its consequences instead
  # (`Playthrough::Drift`). What this reads is a place the story really has,
  # asserted as somewhere the player just walked into.
  #
  # THE GRAMMAR IS THE PLAYER, A MOVEMENT VERB AND A DESTINATION, in that order,
  # in one sentence: "you step back into the office", "You step into the Long
  # Hallway". A mention is not an arrival -- "the door to the hallway stands
  # ajar" and "Mournwell Lane is visible through the window" name a place and
  # match nothing here. The preposition is required for the same reason: it is
  # what makes the place the destination of the verb rather than its scenery.
  #
  # MEASURED BEFORE IT SHIPPED, on 224 real passages -- the 92 in
  # `eval_corpus.json` and the 132 whole-run narrations from the four-arm lab
  # sweep. It detects 7 arrival assertions and every one of the 7 names the room
  # the records had already moved the player into, so it raises ZERO flags:
  # 7 detections, 7 agreements, no false positives. A check that cannot fire
  # would look the same from here, which is why `Story::Audit::ArrivalTest`
  # takes one of those real sentences and moves the record instead -- the
  # sentence that agreed now contradicts, and the check says so. An eighth real
  # arrival is given up to the negation guard and pinned there.
  # ------------------------------------------------------------------------

  # Verbs that take a person from one place to another. `run`, `flee` and
  # `climb` are here; `look`, `lean` and `reach` are deliberately not, because
  # they are what prose does at a threshold without crossing it.
  MOVEMENT_VERBS = /\b(?:step|steps|stepped|stepping|walk|walks|walked|walking|
                       enter|enters|entered|entering|cross|crosses|crossed|crossing|
                       slip|slips|slipped|duck|ducks|ducked|climb|climbs|climbed|
                       descend|descends|descended|ascend|ascends|ascended|
                       go|goes|went|pass|passes|passed|move|moves|moved|
                       push|pushes|pushed|stride|strides|strode|
                       emerge|emerges|emerged|head|heads|headed|
                       return|returns|returned|retreat|retreats|retreated|
                       run|runs|ran|flee|flees|fled)\b/xi

  # What makes the place the destination rather than the view. "to" is included
  # and "toward" is not: crossing TO somewhere arrives, crossing TOWARD it does
  # not.
  TOWARDS = /\b(?:in\s?to|into|onto|on\s+to|out\s+into|through\s+into|to)\s+(?:the\s+|your\s+)?/i

  # One place the narration says the player walked into.
  Arrival = Data.define(:name, :sentence)

  # Every arrival the prose asserts, out of `names` -- the places the records
  # know, as `.place_names` derives them.
  def arrival_claims(text, names)
    body = text.to_s
    return [] if body.blank? || names.empty?

    found = []

    sentences(body).each do |sentence|
      next if sentence.match?(NEGATED_ARRIVAL)

      names.each do |name|
        pattern = /\byou\b[^.!?;:]{0,40}?#{MOVEMENT_VERBS}[^.!?;:]{0,40}?#{TOWARDS}#{Regexp.escape(name)}\b/i
        found << Arrival.new(name: name, sentence: sentence.strip) if sentence.match?(pattern)
      end
    end

    # ONE PER NAME. A paragraph that says the player walked into the hallway
    # twice is one wrong claim, not two, on the same rule `.third_person_references`
    # and `Story::Audit#items_elsewhere` follow.
    found.uniq(&:name)
  end

  # A movement the sentence takes back. "You do not step into the hallway" and
  # "you cannot cross into the Circle" are the arrival grammar exactly, and the
  # opposite of an arrival.
  NEGATED_ARRIVAL = /\b(?:not|never|cannot|can't|won't|would\s+not|without|no\s+way|neither|n't)\b/i

  # THE NAMES A PLACE CAN BE CALLED, as the records hold it: the full name, and
  # the last substantial word of it on its own, because prose says "the office"
  # and "the closet" far more often than "Ward Office 12" and "The Supply
  # Closet".
  #
  # THE STOP LIST IS WHAT KEEPS THE ALIAS HONEST. A room whose name ends in
  # "Room", "Place" or "Area" has a last word that is a common noun for
  # anywhere at all, and "you step into the room" would then be an arrival
  # claim about a specific location every time the prose used the ordinary
  # English word. Those names contribute no alias and are matched in full only.
  GENERIC_PLACE_WORDS = %w[room place area side end floor level part space spot corner house].freeze

  def place_names(name)
    full = name.to_s.strip
    return [] if full.length < Story::Audit::MIN_NAME_LENGTH

    words = full.gsub(/[^\w'\u2019-]/, " ").split
    tail = words.reverse.find { |word| word.match?(/\A[a-z]/i) && word.length >= Story::Audit::MIN_NAME_LENGTH }

    names = [ full ]
    names << tail if tail && tail.casecmp(full).nonzero? && GENERIC_PLACE_WORDS.exclude?(tail.downcase)
    names
  end

  # THE NAMES A THING CAN BE CALLED, on the same rule and for the same reason.
  # `Item#name` is what the records call it -- "Ward Office 12 daybook" -- and
  # no narration in 132 whole-run passages ever wrote that string. Every one of
  # them wrote "daybook". Without the alias `item_not_held` is live and silent,
  # which reads as a clean result and is the one failure mode
  # `Story::Audit`'s header warns about.
  def item_names(item)
    name = item.respond_to?(:name) ? item.name : item

    place_names(name)
  end

  # ------------------------------------------------------------------------
  # THE PROSE ARGUES WITH THE TRANSITION THE TURN ACTUALLY MADE.
  #
  # Every other predicate here reads a passage against a STATE -- where the
  # player is, what the records say they hold. These two read it against a
  # CHANGE, which is what `Scene#resolved_action` and `Scene#acted_on` made
  # possible: the app owns `take` and `drop` outright (`Playthrough::Turn`
  # moves the row before any prose exists), so on a turn recorded as one of
  # them the state before the turn is not in question either.
  #
  #   on a recorded `take`  the item was NOT the player's a moment ago. Prose
  #                         saying it already was denies the pickup the app
  #                         just made -- `prior_possession_claims`.
  #   on a recorded `drop`  the item WAS the player's a moment ago. Prose
  #                         lifting it off a floor or a wall invents a pickup
  #                         that never happened -- `invented_pickup_claims`.
  #
  # THE CAPTAIN'S COMPLAINT BEHIND THEM: *"losing the location of the ledger
  # when it is put down and picked up"*, seen across all four model arms and
  # filed as `ta-narrator-invents-exit`. `Playthrough::Turn#taken_fact` hands
  # the narrator the right sentence and the narrator writes the opposite, on
  # 28 of the 32 take turns of the 480-turn baseline of 2026-09-03. It took a
  # person reading a whole run to find it, because no check could see a change.
  #
  # MEASURED BEFORE THEY SHIPPED, on 248 real passages that are not transition
  # turns, and on 143 that are:
  #
  #   eval_corpus.json (92)      take grammar 0 detections, drop grammar 2
  #   narration_corpus.json (24) take grammar 0 detections, drop grammar 2
  #                              (the same two lab narrations, which
  #                              `eval_corpus.json` also carries)
  #   whole_run_corpus.json      take grammar 6 detections, ALL SIX on the 12
  #   (132, records declared)    turns recorded as `take`; drop grammar 0
  #   transition_corpus.json     28 of 32 recorded takes, 4 of 32 recorded
  #   (119, the 2026-09-03       drops on the baseline set
  #    baseline and three
  #    smaller sets)
  #
  # Not one of the four drop detections outside the transition corpus is on a
  # turn recorded as a `drop`, so neither check raises a single FLAG on any of
  # the three existing corpora. `Story::Audit::TransitionTest` pins all of it,
  # detections and flags apart, because a check that cannot fire looks exactly
  # like a clean result.
  # ------------------------------------------------------------------------

  # Verbs that lift a thing off something. `set`, `place` and `lay` are
  # deliberately absent: they are how putting a thing DOWN is written, which is
  # the turn this reads.
  PICKUP_VERBS = %w[
    lift lifts lifted lifting pick picks picked scoop scoops scooped
    retrieve retrieves retrieved gather gathers gathered hoist hoists hoisted
    grab grabs grabbed snatch snatches snatched collect collects collected
    take takes took taking pull pulls pulled draw draws drew raise raises raised
  ].freeze

  # One sentence that argues with the transition.
  Claim = Data.define(:name, :sentence)

  # THE PROSE SAYS THE PLAYER ALREADY HAD IT.
  #
  # Two grammars, and `already` is required by both. That one word is what
  # separates a denial from a description: "the slate is heavy in your hands"
  # is what a good take narration says AFTER the pickup and is correct, and
  # "you already hold the slate" is the same sentence claiming the pickup was
  # never needed. Nothing here reads a possession claim on its own --
  # `Story::Audit#possession_claimed?` already does that, against a different
  # record, for a different question.
  #
  #   1. the player, `already`, a possession verb, the name:
  #      "You already hold the Assize tide-slate"
  #   2. the name, `already`, and the name on the player's person:
  #      "The Ward Office 12 daybook is already in your hands",
  #      "You reach for the daybook, but it is already in your hands"
  #
  # WHAT IT KNOWINGLY MISSES, and it is four of the 32 baseline takes: the
  # narration that denies the pickup by handing the thing to somebody else --
  # "your fingers close on empty air, Odile Vance has already taken it", of a
  # world whose protagonist IS Odile Vance. That sentence says the player does
  # NOT have it, which is the opposite claim, and reading it needs the
  # protagonist's name rather than the item's. `third_person_protagonist`
  # catches every one of the four from its own side.
  def prior_possession_claims(text, names)
    verbs = Regexp.union(Story::Audit::POSSESSION_VERBS)
    places = Regexp.union(Story::Audit::ON_THE_PERSON)

    claims(text, names) do |sentence, word|
      sentence.match?(/\byou\b[^.!?;:]{0,40}?\balready\b[^.!?;:]{0,30}?\b#{verbs}\b[^.!?;:]{0,40}?\b#{word}\b/i) ||
        sentence.match?(/\b#{word}\b[^.!?;:]{0,80}?\balready\b[^.!?;:]{0,20}?\b(?:in|on|at|against|under)\s+your\s+(?:#{places})\b/i)
    end
  end

  # THE PROSE PICKS UP WHAT THE TURN PUT DOWN.
  #
  # The player, a pickup verb, the name, and then where it came FROM -- in that
  # order, in one sentence. The source is what makes it a pickup rather than a
  # description of the hand that is already holding it, and it is also the one
  # guard this needs: taking a thing out of your own coat is not picking it up
  # off the floor, so a source on the player's person (`ON_THE_PERSON`, with or
  # without a determiner -- prose writes "from the satchel" as readily as "from
  # your satchel") ends the match.
  #
  # "You lift the slate and set it on the bench" is NOT flagged and must not
  # be: lifting a thing out of your own hands is what putting it down is. Five
  # of the 32 baseline drops read that way and none of them is a defect.
  #
  # WHAT IT KNOWINGLY MISSES: the same sentence written about a name the
  # records do not hold. "You lift the slate from the flagstones" of an item
  # recorded as the "Assize tide-slate" matches nothing, because `.item_names`
  # gives "Assize tide-slate" and "tide-slate" and prose is free to write
  # "slate". That is the alias rule the whole sweep works to and widening it
  # here would move counts three other checks are pinned on.
  def invented_pickup_claims(text, names)
    verbs = Regexp.union(PICKUP_VERBS)
    places = Regexp.union(Story::Audit::ON_THE_PERSON)

    claims(text, names) do |sentence, word|
      sentence.match?(
        /\byou\b[^.!?;:]{0,30}?\b#{verbs}\b[^.!?;:]{0,40}?\b#{word}\b[^.!?;:]{0,15}?
         \bfrom\b(?!\s+(?:the\s+|your\s+|his\s+|her\s+|their\s+|its\s+)?(?:#{places})\b)/xi
      )
    end
  end

  # ------------------------------------------------------------------------

  # Sentences, split on a terminator followed by whitespace -- the same split
  # `Story::Audit#excerpt` makes, kept identical so an excerpt and a flag can
  # never quote different spans of the same passage.
  def sentences(text) = text.to_s.split(/(?<=[.!?])\s+/)

  private

  # THE SHAPE BOTH TRANSITION PREDICATES SHARE: every sentence, against every
  # name the item answers to, with the negation guard `Story::Audit` takes
  # everywhere -- a sentence that denies its own claim is the opposite of one.
  #
  # ONE PER NAME, on the same rule `.arrival_claims` and
  # `Story::Audit#items_elsewhere` follow: a passage that says the same wrong
  # thing twice is one wrong claim.
  def claims(text, names)
    body = text.to_s
    return [] if body.blank? || names.empty?

    found = []

    sentences(body).each do |sentence|
      next if sentence.match?(Story::Audit::NEGATIONS)

      names.each do |name|
        found << Claim.new(name: name, sentence: sentence.strip) if yield(sentence, Regexp.escape(name))
      end
    end

    found.uniq(&:name)
  end

  # Each sentence with the offset it starts at in the whole passage, which is
  # what the quotation guard needs: a quoted span is found in the passage and
  # compared against a match found in one sentence.
  def each_sentence(text)
    offset = 0

    sentences(text).each do |sentence|
      at = text.index(sentence, offset) || offset
      offset = at + sentence.length
      yield sentence, at
    end
  end

  def quoted_spans(text)
    text.enum_for(:scan, QUOTED).map { Regexp.last_match.begin(0)...Regexp.last_match.end(0) }
  end

  # Which of the three grammars this occurrence is, or nil for a mention.
  def reference_kind(sentence, match)
    return :possessive if match[1]
    return :sentence_subject if sentence[0...match.begin(0)].match?(/\A\s*[*_"“'\[(]*\z/)
    return :coreference if sentence[match.end(0)..].to_s.match?(PRONOUNS)

    nil
  end
end
