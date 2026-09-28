# Store actual request bytes, then replay the stored answers through today's
# engine builders. Each narrator hash therefore includes its own particular reaction
# and verified receipt; comparisons never pretend that two live reactions are
# the same fixed string. A changed request is detected without a paid call.
module Eval::Dialogue::Version
  # The engine's request for one pass, as a set stores it.
  def self.request(built)
    built.slice("system", "user", "schema", "history")
  end

  def self.digest(requests) = Digest::SHA256.hexdigest(JSON.generate(requests))

  def self.rebuild(row)
    previous_key = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key ||= "offline-dialogue-replay"
    kase = Eval::Dialogue::CORPORA.keys.flat_map { |corpus| Eval::Dialogue.cases(corpus) }
                                  .find { |entry| entry.fetch("id") == row.fetch("id") }
    raise ArgumentError, "unknown case #{row.fetch('id')}" unless kase
    Eval::Classifier::Arm.parse(Eval::Dialogue.model).pinned do
      Eval::Dialogue::Bench.new.read(kase, rep: row.fetch("rep"), replay: row)
    end
  ensure
    RubyLLM.config.openrouter_api_key = previous_key
  end
end
