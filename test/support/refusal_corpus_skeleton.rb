# HOW THE REFUSAL CORPUS IS CHECKED IN WITHOUT CHECKING IN WHAT IT SAYS.
#
# `BaseAgent::RefusalPrecisionTest` measures the detector against 207 responses
# two remote models actually produced. That is the whole value of it: the flags
# are a fact about real prose rather than about prose somebody wrote to pass.
# But the prose is what the models said when asked for explicit sexual content,
# self-harm and slurs, and THIS REPOSITORY IS PUBLIC. Carrying it verbatim
# publishes it.
#
# So the corpus ships REDUCED. `RefusalCorpusSkeleton.of` is the reduction,
# applied uniformly to every record, and
# `test/fixtures/files/refusal_corpus.skeleton.json` is its output. Nothing
# hand-tuned, nothing per-record: one function, 207 times.
#
# WHY NOT JUST KEEP THE ELEVEN REFUSALS AND DROP THE REST. It was tried, and
# measured, and it does not work -- the measurement is in
# `data/ta-refusal-range/report.md`. The eleven flagged responses are not
# explicit and could be published as they are, but they only prove RECALL. The
# other 108 are what prove PRECISION, and the prose already checked in cannot
# replace them:
#
#                                   quote-stripper  opening-window  list rule
#   the 108 compliant responses           13              2             3
#   narration_corpus.json + seeds          0              0             0
#
# Those columns count the records that WOULD be flagged if that rule were
# removed -- the near misses, which are the only records that test anything.
# Thirteen responses in the corpus are false positives prevented solely by the
# quote-stripper. In the 29 passages of ordinary narration this repository
# ships, that count is zero in all three columns, so "0 false positives" over
# them is not a weaker measurement, it is a rule that never came close to
# firing. And the shape is not separable from the subject: all 13 near misses
# came from charged prompts and none from the 16 benign ones, because a charged
# prompt is what makes an NPC talk about itself in the first person up front,
# which is the one shape the quote-stripper has to survive.
#
# WHAT SURVIVES, and why exactly this and no more. `BaseAgent::Refusal` reads a
# STRUCTURE, not a meaning -- that is its whole design, argued in its own header
# -- and a structure is separable from the words that carry it. Three rules,
# and what each one needs:
#
#   QUOTED_DIALOGUE  the positions of " “ ” and \n, and the exact LENGTH of
#                    every span between them, because the gsub replaces a
#                    quoted span with one space and so shortens the text
#   FIRST_PERSON     a capital `I`, its word boundaries, and its offset -- the
#                    opening is the first 300 characters AFTER the strip, so
#                    every character before it has to keep its width
#   LIST             line starts, leading whitespace, and the literal
#                    - * • and 1. 2) markers
#   CRISIS_RESOURCES literal strings, and those alone cannot be reduced at all
#
# Hence the rule, one character at a time:
#
#   * a span matching `BaseAgent::Refusal::CRISIS_RESOURCES` is kept VERBATIM.
#     It is the one predicate that reads words, so its words have to stay. They
#     are "988", "741741" and the names of published crisis lines: public
#     safety boilerplate, and the only English in the file.
#   * everywhere else, every LETTER becomes `x`, except a capital `I`, which is
#     the pronoun the detector looks for.
#   * everything that is not a letter -- whitespace, newlines, quotation marks,
#     bullets, digits, punctuation -- is kept verbatim.
#
# One character in, one character out, so every offset in the file is the
# offset it had in the response. `x` is a word character and so is every letter
# it replaces, in Ruby's `\b` as well as in `\w`, INCLUDING the accented and CJK
# characters in this corpus -- checked, not assumed, in
# `RefusalCorpusSkeletonTest`. Every regex in the detector therefore matches at
# exactly the same offsets, which is not an argument, it is a claim, and it was
# settled by running both: the same flag list, record for record, on all 207,
# 0 mismatches. That run is in the pull request and in the report; it cannot be
# a test here, because passing it requires the prose this file exists to avoid.
#
# WHAT IS GONE, said plainly. Words. A skeleton reads
#
#     "Xxx xxxx xxx xxxxx," xxx xxxx. "X xxx'x xxxx xxx."
#
# and there is no key: the mapping is many-to-one and lossy in the direction
# that matters. It is not an encoding of the response, it is a measurement of
# one, and the response cannot be got back out.
#
# THE TRADE, because it is real and should not be found out later. This corpus
# can re-measure any change to the detector that reads STRUCTURE -- a different
# opening window, a different quote-stripper, more bullet characters, a
# different first-person rule, or a NARROWER crisis watchlist. All of those are
# computed from what the skeleton still carries.
#
# It CANNOT re-measure a change that reads new WORDS: a phrase list, an "as an
# AI" pattern, or a WIDER crisis watchlist, since a string added to the
# watchlist tomorrow was reduced to `x`es today and the skeleton cannot say
# whether it was ever there. That is the price, and it is accepted for two
# reasons. The first is that any reduction which could answer that question is
# one that carries the words, which is the thing being avoided. The second is
# that this detector is structural ON PURPOSE, measured against the word-list
# version and better than it in both directions -- so the changes the skeleton
# supports are the changes this project has already committed to making.
#
# TO REGENERATE, from the raw sweep, which is kept privately in
# `data/ta-refusal-range/lab/results-*.jsonl` and is not in this repository:
#
#   bin/rails runner -e test '
#     require Rails.root.join("test/support/refusal_corpus_skeleton")
#     raw  = JSON.parse(File.read(ARGV[0]))
#     rows = raw.map { |r| r.except("text").merge("skeleton" => RefusalCorpusSkeleton.of(r["text"])) }
#     File.write("test/fixtures/files/refusal_corpus.skeleton.json", JSON.pretty_generate(rows) + "\n")
#   ' raw_corpus.json
module RefusalCorpusSkeleton
  # The pronoun `BaseAgent::Refusal::FIRST_PERSON` looks for, and the only
  # letter that means anything to the detector. Case-sensitive there, so a
  # lowercase `i` is not it and is reduced like any other letter.
  PRONOUN = "I"

  # What every other letter becomes. A word character, so `\b` falls exactly
  # where it fell.
  FILLER = "x"

  # Every letter, in any script. Ruby's `[[:alpha:]]` is Unicode-aware and so
  # is `\b`, which is what makes the substitution safe for the accented and CJK
  # characters this corpus happens to contain.
  LETTER = /[[:alpha:]]/

  # The reduction. Uniform, deterministic, length-preserving, and idempotent.
  def self.of(text)
    text = text.to_s
    out = +""
    pos = 0

    # Leftmost-first and non-overlapping, which is how the watchlist itself
    # scans -- so the spans kept here are exactly the spans that predicate
    # reads.
    while (found = BaseAgent::Refusal::CRISIS_RESOURCES.match(text, pos))
      out << blank(text[pos...found.begin(0)])
      out << found[0]
      pos = found.end(0)
    end

    out << blank(text[pos..].to_s)
  end

  # One character in, one character out.
  def self.blank(span)
    span.gsub(LETTER) { |letter| letter == PRONOUN ? PRONOUN : FILLER }
  end
end
