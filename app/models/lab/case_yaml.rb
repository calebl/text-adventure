# HOW A LAB WRITES A CORPUS CASE OUT, and it is two rules about YAML shared by
# the two things that emit one.
#
# WHY IT IS A MODULE AND NOT A SECOND COPY. `Lab::Realization::Promotion` and
# `Lab::Exits::Promotion` both print a case for a person to paste into
# `test/fixtures/files/realization_corpus.yml`, and both had the same two
# problems to solve: a name somebody typed may not be a YAML string, and a
# teaser and a `why` are prose that has to be folded. Two copies of the quoting
# rule would be two answers to *is this name safe to write bare*, and the one
# that was wrong would put a case in the corpus that YAML read as a mapping.
#
# NEITHER METHOD DECIDES WHAT A CASE CARRIES. That is each promotion's own
# argument -- what may be promoted, what must not be, and what a person still
# has to settle -- and those headers are where it belongs.
module Lab::CaseYaml
  # A BLOCK SCALAR FOR THE LONG FIELDS, which is how every `why` in the corpus is
  # already written -- and `>-` rather than `|` because a teaser and a `why` are
  # prose and the line breaks are the file's, not the sentence's.
  def folded(key, text)
    return [] if text.blank?

    [ "  #{key}: >-", *text.to_s.squish.scan(/.{1,88}(?:\s|$)/).map { |chunk| "    #{chunk.strip}" } ]
  end

  # A NOTE, AS WRAPPED COMMENT LINES. A note is prose, and the emitted case is
  # read in a fixed-width block on a lab page -- so an unwrapped one runs off the
  # right of it, and the one thing a person must be able to do with this text
  # before pasting it is READ it. `#folded`'s width, `#` on every line so the
  # YAML stays a comment however it wraps, and a hanging indent so a wrapped note
  # is still tellable from the next one.
  #
  # THE WRAPPING IS THE EMITTER'S AND NOT THE NOTE'S: `#notes` returns whole
  # sentences, so a caller that wants to assert on one is not asserting on where
  # the lines happened to break.
  def commented(sentences)
    Array(sentences).flat_map { |note|
      note.to_s.squish.scan(/.{1,84}(?:\s|$)/).map.with_index { |chunk, line|
        "  #{line.zero? ? "#" : "#  "} #{chunk.strip}"
      }
    }
  end

  # QUOTED WHENEVER YAML WOULD READ IT AS ANYTHING BUT A STRING, which for a
  # place somebody typed is more often than a reader expects: a name beginning
  # with a `#`, holding a `:` or spelled `no` is a comment, a mapping and a
  # boolean.
  def scalar(value) = value.to_s.match?(/\A[A-Za-z][^:#]*\z/) ? value.to_s : value.to_s.inspect
end
