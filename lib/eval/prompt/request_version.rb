# Play the real turn to its request boundary, on a staged copy nobody keeps.
# The engine plays the case exactly as a paid pass plays it, and every call it
# makes is answered with fixed words (`Eval::EngineCalls::Canned`), so nothing
# reaches a provider; the request captured is the one the engine asked. An
# ending case's prelude is answered the same way, and EndingVersion replaces
# its fields to identify the stable scaffold. Legacy digests still use the
# synthetic assembly, never scored prose.
module Eval::Prompt::RequestVersion
  extend self

  PRELUDE = Eval::EngineCalls::PRELUDE

  def offline(corpus = Eval::Prompt.corpus)
    designated, captured, ending = capture_all(corpus)
    requests = designated.transform_values { |kase| captured.fetch(kase.id) }
    legacy = { prompt_digest: Eval::Prompt::Version.digest(requests.map { |shape, request| "#{shape}\n#{request[:user]}" }),
               instructions_digest: Eval::Prompt::Version.digest(requests.values.map { |request| request[:system] }.uniq.sort) }
    identity = if ending
      scaffolds = captured.transform_values { |request| request.fetch(:ending_scaffold) }
      Eval::Prompt::EndingVersion.identity(scaffolds, corpus)
    else
      Eval::RequestIdentity.of(requests.transform_values { |request| request.except(:ending_scaffold) })
    end
    legacy.merge(request_identity: identity)
  end

  # The designated requests of a corpus without an ending, shape => request:
  # exactly what `#offline`'s identity is taken over.
  def requests(corpus = Eval::Prompt.corpus)
    designated, captured, ending = capture_all(corpus)
    raise ArgumentError, "an ending corpus is identified by its scaffolds" if ending

    designated.transform_values { |kase| captured.fetch(kase.id).except(:ending_scaffold) }
  end

  # [shape => designated case, case id => captured request, whether every case is an ending].
  def capture_all(corpus)
    designated = corpus.cases.group_by { |kase| kase.shape.to_s }.sort.to_h
                       .transform_values { |cases| cases.min_by(&:id) }
    ending = corpus.cases.all?(&:ending?)
    cases = ending ? corpus.cases.sort_by(&:id) : designated.values
    captured = if corpus.path.to_s == Eval::Prompt::BRANCHES_CORPUS.to_s
      # A pending branch moment is staged by its producer and narrated with
      # nothing played (`Eval::Prompt::Branches`).
      Eval::Prompt::Branches.capture(corpus).transform_keys { |shape| designated.fetch(shape).id }
                            .transform_values { |row| row.fetch("request").symbolize_keys }
    else
      bench = Eval::Prompt::Bench.new(corpus: corpus, io: nil)
      cases.to_h { |kase| [ kase.id, capture(bench, corpus, kase) ] }
    end
    [ designated, captured, ending ]
  end

  def capture(bench, corpus, kase)
    answering = Eval::EngineCalls::Canned.new
    reading = nil
    Eval::Classifier::Stage.on_file([ corpus.position(kase.position) ],
                                    label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                    roots: Eval::Prompt::WORLD_ROOTS) do |stages, file|
      reading = bench.send(:play_case, kase, stages.fetch(kase.position), Eval::Classifier::Arm.parse("offline"), 0,
                           file, answering: answering)
    end
    raise "#{kase.id} did not play offline: #{reading.error}" if reading.failed?

    receipt = kase.ending? ? answering.receipts.find { |call| call.purpose == Eval::Prompt::Bench::ENDING } : answering.receipts.first
    raise "No designated request captured for #{kase.id}" unless receipt

    request = receipt.request
    request[:ending_scaffold] = reading.ending_request.fetch(:scaffold) if kase.ending?
    request
  end
end
