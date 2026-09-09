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

  # QUOTED WHENEVER YAML WOULD READ IT AS ANYTHING BUT A STRING, which for a
  # place somebody typed is more often than a reader expects: a name beginning
  # with a `#`, holding a `:` or spelled `no` is a comment, a mapping and a
  # boolean.
  def scalar(value) = value.to_s.match?(/\A[A-Za-z][^:#]*\z/) ? value.to_s : value.to_s.inspect
end
