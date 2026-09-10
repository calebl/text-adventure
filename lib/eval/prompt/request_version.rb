# Run the real turn to its request boundary, inside rolled-back staging.
# No provider conversation is built. Synthetic ending preludes only reach the
# request boundary; EndingVersion replaces their fields to identify the stable
# scaffold. Legacy digests still use the synthetic assembly, never scored prose.
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
    bench = Eval::Prompt::Bench.new(corpus: corpus, io: nil)
    designated = corpus.cases.group_by { |kase| kase.shape.to_s }.sort.to_h
                       .transform_values { |cases| cases.min_by(&:id) }
    ending = corpus.cases.all?(&:ending?)
    cases = ending ? corpus.cases.sort_by(&:id) : designated.values
    captured = cases.to_h do |kase|
      request = nil
      Eval::Classifier::Stage.open([ corpus.position(kase.position) ],
                                   label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                   roots: Eval::Prompt::WORLD_ROOTS) do |stages|
        request = capture(kase) do
          bench.send(:play_case, kase, stages.fetch(kase.position), Eval::Classifier::Arm.parse("offline"), 0)
        end
      end
      raise "No designated request captured for #{kase.id}" unless request
      [ kase.id, request ]
    end
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

  def capture(kase)
    previous = Thread.current[KEY]
    catch(:eval_request_captured) do
      Thread.current[KEY] = lambda do |agent, prompt, block|
        if !kase.ending? || agent.purpose == "ending"
          request = Eval::RequestIdentity.request(agent.instructions, prompt, agent.schema)
          request[:ending_scaffold] = Eval::Prompt::EndingVersion.current.fetch(:scaffold) if kase.ending?
          throw :eval_request_captured, request
        end
        if agent.schema
          raise "Unexpected structured ending prelude" unless agent.purpose == "arrival" && agent.schema == Scene::Schema
          Response.new({ "description" => PRELUDE, "summary" => PRELUDE })
        else
          block&.call(Response.new(PRELUDE))
          Response.new(PRELUDE)
        end
      end
      yield
      nil
    end
  ensure
    Thread.current[KEY] = previous
  end
end
