# FULL REQUEST IDENTITY, PER CASE AND CALL. No prose or engine pick is scrubbed:
# upstream assistant exchanges are fixed fixtures and belong to the request.
# Shared request canonicalization covers system, user, emitted schema and
# ordered history. Keep the original full-length digest so kept sets replay.
module Eval::Genesis::Version
  extend self

  def canonical(value) = Eval::RequestIdentity.canonical(value)

  def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))

  def offline(cases = Eval::Genesis.corpus.cases)
    cases.to_h do |kase|
      [ kase.id, Eval::Genesis::Stage.open(kase) { |stage|
        stage.requests.to_h { |request| [ request.call, digest(request.identity) ] }
      } ]
    end
  end
end
