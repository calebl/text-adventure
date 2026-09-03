# THE THREE THINGS THAT CAN BE READ OUT OF A PASSAGE ALONE, with no database
# behind them.
#
# Every predicate here is pure: text in, a boolean or a list of matches out.
# That is deliberate and it is what makes the checks measurable. `Story::Audit`
# supplies the records that turn a match into a flag -- the protagonist's real
# name, whether the player actually moved -- and `Story::Scoreboard::Corpus`
# supplies the same facts from a checked-in file, so the SAME code reads the
# live database and the frozen corpus and the two cannot drift apart.
#
# WHY THESE THREE AND NOT OTHERS. They are the errors the captain noticed
# unaided while playing, in his own words: prose that stops mid-sentence, the
# protagonist written as somebody standing opposite him, and a door closing at
# his back in a room he never left. Nothing here was invented because it
# sounded checkable. See `Story::Audit`'s header for the two prose heuristics
# this project has already measured and killed.
#
# PRECISION, MEASURED. Against 92 real passages -- 54 stored `Scene`
# descriptions, 14 `Interaction` actions and the 24 narrations in
# `narration_corpus.json` -- these three raise 17 flags and every one of them is
# a true positive, with zero flags on the 24 narrations from the lab sweep.
# `Story::Scoreboard::CorpusTest` pins that, one flag at a time. The recall is
# worse than the precision on purpose, and each method says where it knowingly
# misses.
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
  def protagonist_names(character)
    return [] if character.nil?

    ([ character.fullname, character.nickname ] + character.fullname.to_s.split(/\s+/))
      .map { |name| name.to_s.gsub(/[^\w'’-]/, " ").strip }
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

  # Sentences, split on a terminator followed by whitespace -- the same split
  # `Story::Audit#excerpt` makes, kept identical so an excerpt and a flag can
  # never quote different spans of the same passage.
  def sentences(text) = text.to_s.split(/(?<=[.!?])\s+/)

  private

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
