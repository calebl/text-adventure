# FULL REQUEST IDENTITY, PER CASE AND CALL. No prose or engine pick is scrubbed:
# upstream assistant exchanges are fixed fixtures and belong to the request.
# Until the shared schema-digest instrument lands this is explicit canonical
# JSON over system, user, emitted schema and ordered history, all retained.
module Eval::Genesis::Version
  extend self

  def canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |child| canonical(child) }
    when Array then value.map { |child| canonical(child) }
    else value
    end
  end

  def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))

  def offline(cases = Eval::Genesis.corpus.cases)
    cases.to_h do |kase|
      [ kase.id, Eval::Genesis::Stage.open(kase) { |stage|
        stage.requests.to_h { |request| [ request.call, digest(request.identity) ] }
      } ]
    end
  end
end
