# The runner for the seed-world arc re-baseline, adapted from the previous
# re-baseline's runner beside it under doc/evidence. It changes no prompt, schema,
# sampling parameter or scoring. Before every model call it reserves the
# registry price of a bounded input plus the model's entire output allowance,
# and refuses the call if the ledger's accounted spend plus that reservation
# would pass LIMIT. Transport retries are off, so an unknown charge has exactly
# one reservation. A failed or unreported call keeps its reservation.
require "json"
$stdout.sync = true
module ArcRebaselineSpend
  # Two groups, two ceilings: the priced sets share receipts.json under $2.00;
  # the cascade sets keep their own ledger under $1.00, beside the OpenRouter
  # credit readings that bracket them.
  LIMIT = Float(ENV.fetch("LEDGER_LIMIT", "2.0"))
  PATH = Rails.root.join("doc/evidence/seed-world-arcs-rebuy", ENV.fetch("LEDGER", "receipts.json"))
  class Halt < Exception; end

  def self.edit
    File.open(PATH, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      raw = file.read
      ledger = raw.empty? ? { "limit_usd" => LIMIT, "calls" => [] } : JSON.parse(raw)
      result = yield ledger
      file.rewind
      file.write(JSON.pretty_generate(ledger) + "\n")
      file.truncate(file.pos)
      file.flush
      result
    end
  end

  def ask(prompt = nil, **options, &block)
    pinned = BaseAgent::REMOTE_MODEL_IDS.first
    price = Eval::Cost.price(model.model_id)
    unless model.model_id == pinned && price.input_per_million.to_f.positive? && price.output_per_million.to_f.positive?
      raise Halt, "Unpriced or unpinned model: #{model.model_id}"
    end
    schema = (to_llm.schema rescue nil)
    bytes = JSON.generate([ messages.map { |message| [ message.role, message.content.to_s ] }, prompt.to_s, schema ]).bytesize
    output_bound = model.max_output_tokens
    raise Halt, "Missing output bound" unless output_bound&.positive?
    reserve = price.of(bytes + 4096, output_bound)
    row = { "set" => ENV.fetch("SET"), "purpose" => purpose, "reserved_usd" => reserve,
            "accounted_usd" => reserve, "state" => "reserved" }
    index = ArcRebaselineSpend.edit do |ledger|
      spent = ledger["calls"].sum { |entry| entry.fetch("accounted_usd") }
      raise Halt, "Task budget cannot reserve another request (#{spent.round(4)} accounted)" if spent + reserve > LIMIT
      ledger["calls"] << row
      ledger["calls"].size - 1
    end
    begin
      response = super
      # RubyLLM 2 reports usage on `Message#tokens`; the flat `input_tokens`
      # readers the earlier harness used answer nil on a persisted message.
      tokens = response.tokens
      usage = { input_tokens: tokens.input, output_tokens: tokens.output, cached_tokens: tokens.cache_read,
                cache_creation_tokens: tokens.cache_write, thinking_tokens: tokens.thinking,
                provider_cost_usd: tokens.reported_cost&.to_f, registry_cost_usd: response.cost&.total&.to_f,
                actual_model: (response.model_id if response.respond_to?(:model_id)) }
      row.merge!(usage.deep_stringify_keys)
      known = usage[:input_tokens] && usage[:output_tokens]
      cost = known && price.of(usage.values_at(:input_tokens, :cached_tokens, :cache_creation_tokens).sum(&:to_i),
                               usage.values_at(:output_tokens, :thinking_tokens).sum(&:to_i))
      row["registry_usage_usd"] = cost
      # THE PROVIDER'S OWN CHARGE WHEN IT REPORTS ONE -- that is the receipt.
      # `cost` counts cached tokens again at the full input price, which is an
      # upper bound and only the fallback for a call with no reported charge.
      row["accounted_usd"] = usage[:provider_cost_usd] || [ cost, usage[:registry_cost_usd] ].compact.max || reserve
      row["state"] = known ? "settled" : "unknown"
      raise Halt, "Provider exceeded reservation" if row["accounted_usd"] > reserve
      response
    rescue Exception => error
      row["error"] = error.class.name
      raise
    ensure
      ArcRebaselineSpend.edit { |ledger| ledger["calls"][index] = row }
    end
  end
end
raise "Use this worktree's scratch database" unless ActiveRecord::Base.connection_db_config.database == "tmp/rebaseline.sqlite3"
RubyLLM.config.max_retries = 0
Chat.prepend(ArcRebaselineSpend)
Rails.application.load_tasks
Rake::Task[ENV.fetch("BENCH_TASK")].invoke
