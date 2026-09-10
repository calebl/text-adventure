# Task-local runner. Preserve prompts, schemas, sampling parameters and bench
# scoring. Disable transport retries so an unknown charge has one reservation.
# Reserve the registry's entire output allowance before each call; never rely
# on expected prose length to enforce the task ceiling. Failed calls retain
# their reservation. This also captures warmups and ending preludes omitted by
# the legacy scored-scene receipts.
require "json"
$stdout.sync = true
module RebaselineSpend
  LIMIT = 2.0
  PATH = Rails.root.join("doc/evidence/ta-bench-rebaseline-stale/receipts.json")
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

  def ask(prompt, **options, &block)
    price = Eval::Cost.price(model.model_id)
    raise Halt, "Unpriced or unpinned model" unless model.model_id == BaseAgent::REMOTE_MODEL_IDS.first && price.input_per_million.positive? && price.output_per_million.positive?
    bytes = JSON.generate([ messages.map { |message| [ message.role, message.content ] }, prompt, to_llm.schema ]).bytesize
    input_bound = bytes + 4096
    output_bound = model.max_output_tokens
    raise Halt, "Missing output bound" unless output_bound&.positive?
    reserve = price.of(input_bound, output_bound)
    row = { "set" => ENV.fetch("SET"), "purpose" => purpose, "reserved_usd" => reserve, "accounted_usd" => reserve, "state" => "reserved" }
    index = RebaselineSpend.edit do |ledger|
      raise Halt, "Task budget cannot reserve another request" if ledger["calls"].sum { |entry| entry.fetch("accounted_usd") } + reserve > LIMIT
      ledger["calls"] << row
      ledger["calls"].size - 1
    end
    begin
      response = super
      usage = Eval::Dialogue::Budget.usage(response)
      row.merge!(usage.deep_stringify_keys)
      known = usage[:input_tokens] && usage[:output_tokens]
      cost = known && price.of(usage.values_at(:input_tokens, :cached_tokens, :cache_creation_tokens).sum(&:to_i), usage.values_at(:output_tokens, :thinking_tokens).sum(&:to_i))
      row["registry_usage_usd"] = cost
      row["accounted_usd"] = [ usage[:provider_cost_usd], cost ].compact.max || reserve
      row["state"] = known ? "settled" : "unknown"
      raise Halt, "Provider exceeded reservation" if row["accounted_usd"] > reserve
      response
    rescue Exception => error
      row["error"] = error.class.name
      raise
    ensure
      RebaselineSpend.edit { |ledger| ledger["calls"][index] = row }
    end
  end
end
raise "Use this worktree's scratch database" unless ActiveRecord::Base.connection_db_config.database == "tmp/rebaseline.sqlite3"
RubyLLM.config.max_retries = 0
Chat.prepend(RebaselineSpend)
Rails.application.load_tasks
Rake::Task[ENV.fetch("BENCH_TASK")].invoke
