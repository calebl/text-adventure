# WHAT A MODEL SAID INSTEAD OF NARRATING, AND HOW THE APP TELLS THE TWO APART.
#
# `Scene::Narrator` and `InteractionAgent`'s second pass are the two unschema'd
# calls in the app (AGENTS.md -> *Talking to models*), so they are the two that
# can come back as prose about the request rather than prose answering it. A
# schema'd call cannot fail this way and is not read here: it either returns the
# Hash it was asked for or `verify_schema_honored!` fails it.
#
# MEASURED, NOT GUESSED, and the measurement is checked in. The corpus is 127
# real prose responses from `minimax/minimax-m3` and `mistralai/mistral-medium-3.1`
# across six content categories, in
# `test/fixtures/files/refusal_corpus.skeleton.json` and pinned by
# `BaseAgent::RefusalPrecisionTest`. `data/ta-refusal-range/report.md` is where
# they came from. The corpus is checked in REDUCED -- every letter replaced by
# `x`, offsets preserved exactly -- because this repository is public and the
# responses are the explicit content the sweep provoked. See
# `RefusalCorpusSkeleton`.
#
# THE RULE, and why it is this rule. A regex for "I can't" is the obvious
# version and it was tried first, on the same corpus, and it fails in both
# directions:
#
#   * It MISSES the refusals that matter. "I'm not going to narrate that.
#     Threatening to harm a child isn't something I'll roleplay" contains no
#     phrase any such list has, and it is the single response that a previous
#     report's 0/5 refusal rate turned on.
#   * It FIRES ON DIALOGUE. The corpus is mostly first-person speech, so "I
#     won't stop until you tell me to" -- a character, mid-scene -- reads as a
#     refusal to any pattern matching on words.
#
# So the signature is STRUCTURAL, and it comes from the narrator's own prompt
# (`Scene::Narrator::INSTRUCTIONS`): the narrator writes in the SECOND person
# and characters speak inside quotation marks, so an unquoted "I" near the top
# is the model talking about itself rather than the world. And a bulleted or
# numbered list is a menu, which that prompt already forbids in as many words.
# Strip the dialogue, read the opening, and look for a list anywhere:
#
#   recall 11/11   false positives 0/76   on minimax/minimax-m3
#   recall  0/11   false positives 0/32   on mistralai/mistral-medium-3.1
#
# The second line is the one that decided the model order: mistral wrote every
# response minimax refused, and nothing it wrote is flagged here, so it is the
# model a flagged response should rotate ONTO. That is how the lists are
# ordered on the path this detector reads: `BaseAgent::PROSE_MODEL_IDS` -- the
# unschema'd, player-read calls, the only ones `verify_not_refused!` looks at
# -- puts minimax first and mistral second, so a refusal lands on the model
# measured to have written it. (`BaseAgent::REMOTE_MODEL_IDS` is the other way
# round for the schema'd calls, which this detector never reads. See the notes
# on both constants.)
#
# WHAT IT CANNOT DO, said plainly so nobody expects it to. It does not catch
# SILENT SOFTENING -- in-fiction, second-person prose that deletes the premise
# it was asked about and reads exactly like compliance. Seven responses in the
# corpus do that and none of them is flagged, deliberately: the only thing that
# separated them from craft was running the same prompt three times and reading
# all three. A detector buys back the hard failures. The soft ones are a
# sampling problem and stay one.
#
# THE WATCHLIST IS NOT A REFUSAL, and it is here because it is the one shape
# the structural rule cannot see: a real-world crisis line delivered INSIDE
# quoted dialogue, by a character, in a world with no telephones. It is a
# separate predicate because the app does a completely different thing with it
# -- see `BaseAgent#ask`. None of these strings has an in-world use, and none
# of them appeared in any of the 55 schema'd character responses in the corpus.
module BaseAgent::Refusal
  # A quoted span, so it can be taken out before the opening is read. Bounded
  # and newline-free so an unterminated quotation mark cannot swallow the rest
  # of the response and hide the model's own voice behind it.
  QUOTED_DIALOGUE = /["“”][^"“”\n]{0,600}?["“”]/

  # Case-sensitive on purpose: `\bI\b` is the pronoun, and a case-insensitive
  # version matches the article-like "i" in nothing useful and the word "I" in
  # every "in", "if" and "it" that starts a sentence once the boundaries slip.
  FIRST_PERSON = /\bI\b|\bI['’](m|ll|ve|d)\b/

  # A menu. `\A` rather than `^` because Ruby's `^` matches after every newline
  # already and the Python this is ported from used a non-multiline `^` plus an
  # explicit `\n` -- keeping both spellings apart is what makes the port
  # faithful rather than merely similar.
  LIST = /(\A|\n)\s*(?:[-*•]\s+|\d+[.)]\s+)/

  # Real-world crisis resources. US-centric because the corpus is: these are
  # the strings the models actually reached for.
  CRISIS_RESOURCES = /\b988\b|741741|Crisis Text Line|Suicide (&|and) Crisis|findahelpline|hotline|Lifeline/i

  # How much of the response counts as "the opening". A refusal announces
  # itself; a narration that mentions "I" three paragraphs in is quoting
  # somebody the quote-stripper missed.
  OPENING = 300

  # Everything wrong with this text, as symbols, or an empty array. The whole
  # measured detector is these three lines; keep them in step with
  # `BaseAgent::RefusalPrecisionTest`, which is what says they still work.
  def self.flags(text)
    text = text.to_s
    found = []
    found << :unquoted_first_person if FIRST_PERSON.match?(text.gsub(QUOTED_DIALOGUE, " ")[0, OPENING].to_s)
    found << :list if LIST.match?(text)
    found << :crisis_resource if CRISIS_RESOURCES.match?(text)
    found
  end

  # The model declined, or answered with a menu. A FAILED CALL: `BaseAgent#ask`
  # rotates past it. Structural flags only -- a crisis response is not a
  # refusal and must not be rotated away from.
  def self.refused?(text)
    flags = flags(text)
    flags.include?(:unquoted_first_person) || flags.include?(:list)
  end

  # The model answered with real-world crisis resources. NOT a failed call and
  # NOT rotated past: the app suppresses it and says something of its own. See
  # `Playthrough::SafetyNotice`.
  def self.crisis_response?(text)
    CRISIS_RESOURCES.match?(text.to_s)
  end
end
