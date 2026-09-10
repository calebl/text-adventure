# Run the real turn to its request boundary, inside rolled-back staging.
# No provider conversation is built. Ending preludes use fixed synthetic prose
# solely to render the ending scaffold; this is never scored as model output.
# This deliberately does not certify equality of generated ending history.
module Eval::Prompt::RequestVersion
  extend self

  PRELUDE = "The measured action is complete.".freeze
  Response = Struct.new(:content)
  KEY = :eval_prompt_request_capture

  module Capture
    def ask(prompt, **options, &block)
      capture = Thread.current[Eval::Prompt::RequestVersion::KEY]
      return super unless capture

      capture.call(self, prompt, block)
    end

    private

    def build_chat
      raise "Offline request capture attempted a provider conversation" if Thread.current[Eval::Prompt::RequestVersion::KEY]

      super
    end
  end

  def offline(corpus = Eval::Prompt.corpus)
    BaseAgent.prepend(Capture) unless BaseAgent.ancestors.include?(Capture)
    requests = {}
    bench = Eval::Prompt::Bench.new(corpus: corpus, io: nil)
    corpus.cases.group_by { |kase| kase.shape.to_s }.sort.each do |shape, cases|
      kase = cases.min_by(&:id)
      Eval::Classifier::Stage.open([ corpus.position(kase.position) ],
                                   label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                   roots: Eval::Prompt::WORLD_ROOTS) do |stages|
        request = capture(kase) do
          bench.send(:play_case, kase, stages.fetch(kase.position), Eval::Classifier::Arm.parse("offline"), 0)
        end
        raise "No designated request captured for #{kase.id}" unless request
        requests[shape] = request
      end
    end
    legacy = { prompt_digest: Eval::Prompt::Version.digest(requests.map { |shape, request| "#{shape}\n#{request[:user]}" }),
               instructions_digest: Eval::Prompt::Version.digest(requests.values.map { |request| request[:system] }.uniq.sort) }
    legacy.merge(request_identity: Eval::RequestIdentity.of(requests))
  end

  def capture(kase)
    previous = Thread.current[KEY]
    catch(:eval_request_captured) do
      Thread.current[KEY] = lambda do |agent, prompt, block|
        if !kase.ending? || agent.purpose == "ending"
          throw :eval_request_captured, Eval::RequestIdentity.request(agent.instructions, prompt, agent.schema)
        end
        raise "Unexpected structured ending prelude" if agent.schema
        block&.call(Response.new(PRELUDE))
        Response.new(PRELUDE)
      end
      yield
      nil
    end
  ensure
    Thread.current[KEY] = previous
  end
end
