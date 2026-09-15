# One funded classifier confirmation, through the existing Bench#read and
# scoring classes. Every completed reading is fsynced before another can be
# reported complete. Resume skips those rows, including failures; a paid ledger
# entry without a corresponding row requires reconciliation, never a retry.
# Provider calls use the shared review budget, not a second allowance.
require "json"
require "digest"
require "fileutils"

module PhysicalClassifierStudy
  MODEL = "mistralai/mistral-medium-3.1".freeze
  REPS = 4
  SET = "physical-classifier-20260910".freeze

  # Only this runner needs concurrent receipts. The budget ledger already
  # serializes reservations across threads/processes; its original process
  # attributes cannot attribute overlapping calls to their individual lines.
  module ThreadReceipts
    def calls = Thread.current[:physical_classifier_calls] ||= []
    def calls=(value)
      Thread.current[:physical_classifier_calls] = value
    end

    def label = Thread.current[:physical_classifier_label]
    def label=(value)
      Thread.current[:physical_classifier_label] = value
    end
  end

  module CaptureRequest
    def ask(prompt, **options, &block)
      actual = PhysicalClassifierStudy.payload(self, prompt)
      PhysicalClassifierStudy.verify_payload!(actual, Thread.current[:physical_classifier_expected],
        used: Thread.current[:physical_classifier_request].present?)
      Thread.current[:physical_classifier_request] = actual
      super
    end
  end

  def self.payload(agent, prompt)
    JSON.parse(JSON.generate({ "system" => agent.instructions, "user" => prompt,
      "schema" => agent.schema&.new&.to_json_schema,
      "history" => agent.chat.messages.order(:id).map { |message| { "role" => message.role, "content" => message.text } } }))
  end

  def self.verify_payload!(actual, expected, used:)
    raise ReviewEvalBudget::Halt, "The reading already made its one permitted call" if used
    raise ReviewEvalBudget::Halt, "Classifier payload differs from the reviewed preflight" unless expected && actual == expected
  end

  def self.offline_payload(classifier, typed)
    agent = classifier.agent
    agent.define_singleton_method(:ask) do |prompt, **|
      throw :physical_classifier_payload, PhysicalClassifierStudy.payload(self, prompt)
    end
    EngineSweep.without_a_model { catch(:physical_classifier_payload) { classifier.classify(typed) } }
  ensure
    agent&.singleton_class&.remove_method(:ask)
  end

  def self.preflight_requests(corpus)
    requests = {}
    Eval::Classifier::Arm.parse(MODEL).pinned do
      first = corpus.lines.first
      Eval::Classifier::Stage.open([ corpus.position(first.position) ]) do |stages|
        requests["0:#{first.id}"] = offline_payload(stages.fetch(first.position).classifier, first.typed)
      end
      # Classifier calls change no offered state. Every repetition uses these
      # same staged records; the paid guard checks actual IDs as well as text.
      Eval::Classifier::Stage.open(corpus.positions) do |stages|
        corpus.lines.each do |line|
          classifier = Playthrough::Classifier.new(Playthrough.find(stages.fetch(line.position).playthrough.id))
          requests[line.id] = offline_payload(classifier, line.typed)
        end
      end
    end
    requests
  end

  class Journal
    attr_reader :directory, :rows

    def initialize(directory, manifest)
      @directory = Pathname.new(directory)
      FileUtils.mkdir_p(@directory)
      @mutex = Mutex.new
      file = @directory.join("protocol.json")
      if file.exist?
        raise "Resume protocol changed" unless JSON.parse(file.read) == JSON.parse(JSON.generate(manifest))
      else
        File.write(file, JSON.pretty_generate(manifest) + "\n")
      end
      @path = @directory.join("readings.jsonl")
      @rows = @path.exist? ? @path.readlines.map { |line| JSON.parse(line) } : []
      @keys = @rows.map { |row| [ row.fetch("rep"), row.fetch("id") ] }
      raise "Duplicate saved readings" unless @keys.uniq.size == @keys.size
    end

    def include?(rep, id) = @mutex.synchronize { @keys.include?([ rep, id ]) }

    def append(row)
      @mutex.synchronize do
        row = JSON.parse(JSON.generate(row))
        key = [ row.fetch("rep"), row.fetch("id") ]
        raise "Duplicate saved reading #{key}" if @keys.include?(key)
        File.open(@path, "a", 0o600) do |file|
          file.puts(JSON.generate(row))
          file.flush
          file.fsync
        end
        @rows << row
        @keys << key
      end
    end
  end

  def self.manifest(concurrency:, set: SET)
    files = Dir.glob(Rails.root.join("app/**/*.rb")) + Dir.glob(Rails.root.join("db/seeds/worlds/*.yml")) +
            Dir.glob(Rails.root.join("lib/world_seed/**/*.rb")) +
            %w[lib/eval/classifier/version.rb lib/eval/classifier/corpus.rb lib/eval/classifier/bench.rb
               test/fixtures/files/classifier_corpus.yml].map { |path| Rails.root.join(path).to_s }
    { "set" => set, "model" => MODEL, "reps" => REPS, "concurrency" => concurrency,
      "corpus_digest" => Eval::Classifier.digest, "corpus_size" => Eval::Classifier.corpus.size,
      "request_identity" => Eval::Classifier::Version.offline,
      "source_files" => files.sort.to_h { |path| [ Pathname.new(path).relative_path_from(Rails.root).to_s, Digest::SHA256.file(path).hexdigest ] },
      "historical_projection" => "The unchanged main339 labels, including its historical give-as-drop label. No historical result is relabelled.",
      "failures" => "Retained, never retried or omitted. Incomplete sets cannot export a baseline.",
      "budget" => "The existing shared EVAL_BUDGET_FILE; unknown charges retain their reservations." }
  end

  def self.serialize(reading, calls:, request:)
    { "id" => reading.id, "rep" => reading.rep, "arm" => reading.arm,
      "answer" => reading.answer&.to_h, "answered_by" => reading.answered_by,
      "raw" => reading.raw, "seconds" => reading.seconds, "error" => reading.error,
      "calls" => calls, "request" => request }
  end

  def self.reading(row, corpus)
    answer = row["answer"] && Eval::Classifier::Corpus::Answer.new(**row.fetch("answer").symbolize_keys.merge(intent: row.dig("answer", "intent").to_sym))
    Eval::Classifier::Bench::Reading.new(line: corpus.lines.find { |line| line.id == row.fetch("id") } || raise("Unknown case"),
      arm: row.fetch("arm"), rep: row.fetch("rep"), answer: answer, answered_by: row["answered_by"],
      raw: row["raw"], seconds: row["seconds"], error: row["error"])
  end

  def self.result(journal, corpus:, identity:, name:, concurrency:, recorded_at: Time.now.utc.iso8601)
    rows = journal.rows
    passes = (1..REPS).map do |rep|
      ordered = corpus.lines.map do |line|
        matches = rows.select { |row| row["rep"] == rep && row["id"] == line.id }
        raise "Incomplete or duplicate reading #{line.id}:#{rep}" unless matches.one?
        reading(matches.first, corpus)
      end
      Eval::Classifier::Bench::Pass.new(arm: MODEL, rep: rep, readings: ordered)
    end
    warm = rows.select { |row| row["rep"].zero? }
    raise "Exactly one retained warmup is required" unless warm.one?
    Eval::Classifier::Result.new(name: name, recorded_at: recorded_at, corpus_size: corpus.size,
      corpus_digest: Eval::Classifier.digest(corpus), request_identity: identity, arms: [ MODEL ], reps: REPS,
      passes: passes, concurrency: concurrency,
      warmups: [ Eval::Classifier::Bench::Warmup.new(arm: MODEL, seconds: warm.first["seconds"],
        residency: :not_local, error: warm.first["error"]) ])
  end

  def self.run(directory:, concurrency: 4, set: SET)
    raise "Concurrency must be between 1 and 4" unless (1..4).cover?(concurrency)
    require ENV.fetch("EVAL_BUDGET_HELPER")
    ReviewEvalBudget.assert_isolated_database!
    protocol = manifest(concurrency: concurrency, set: set)
    journal = Journal.new(directory, protocol)
    corpus = Eval::Classifier.corpus
    preflight_file = Pathname.new(directory).join("requests.json")
    if ENV["EVAL_PREFLIGHT"] == "1"
      raise "Preflight already exists" if preflight_file.exist?
      File.write(preflight_file, JSON.pretty_generate(preflight_requests(corpus)) + "\n")
      return journal
    end
    raise "Reviewed request file changed" unless Digest::SHA256.file(preflight_file).hexdigest == ENV.fetch("EVAL_REQUESTS_SHA256")
    allowed = JSON.parse(preflight_file.read)
    raise "Incomplete request preflight" unless allowed.keys.sort == [ "0:#{corpus.lines.first.id}", *corpus.lines.map(&:id) ].sort

    ReviewEvalBudget.singleton_class.prepend(ThreadReceipts)
    ReviewEvalBudget.install!
    BaseAgent.prepend(CaptureRequest)
    bench = Eval::Classifier::Bench.new(corpus: corpus, arms: [ MODEL ], concurrency: concurrency, io: nil)
    arm = Eval::Classifier::Arm.parse(MODEL)
    prior = ReviewEvalBudget.ledger.snapshot.fetch("entries").map { |entry| entry.fetch("label") }
    mutex = Mutex.new
    stopped = nil
    read_one = lambda do |line, rep, standing|
      next if journal.include?(rep, line.id) || mutex.synchronize { stopped }
      label = "#{set}:#{rep}:#{line.id}"
      raise "Reconcile paid reading before resuming: #{label}" if prior.include?("#{label}:classifier")
      ReviewEvalBudget.label = label
      ReviewEvalBudget.calls = []
      Thread.current[:physical_classifier_request] = nil
      Thread.current[:physical_classifier_expected] = allowed.fetch(rep.zero? ? "0:#{line.id}" : line.id)
      begin
        row = bench.send(:read, line, standing, arm, rep)
        journal.append(serialize(row, calls: ReviewEvalBudget.calls, request: Thread.current[:physical_classifier_request]))
        puts "#{rep}:#{line.id} #{row.error || row.answer}" if journal.rows.size % 25 == 0 || rep.zero?
      rescue ReviewEvalBudget::Halt => error
        # A pre-reservation halt bought nothing. If a request was admitted,
        # retain its failed reading so resumption cannot buy it a second time.
        if ReviewEvalBudget.calls.any?
          row = Eval::Classifier::Bench::Reading.new(line: line, arm: MODEL, rep: rep, answer: nil,
            answered_by: nil, raw: nil, seconds: nil, error: "#{error.class}: #{error.message}")
          journal.append(serialize(row, calls: ReviewEvalBudget.calls, request: Thread.current[:physical_classifier_request]))
        end
        mutex.synchronize { stopped ||= error }
      end
    end
    Eval::Classifier::Bench.exclusive(MODEL) do
      Eval.without_provider_retries do
        arm.pinned do
          first = corpus.lines.first
          Eval::Classifier::Stage.open([ corpus.position(first.position) ]) do |stages|
            read_one.call(first, 0, stages.fetch(first.position))
          end
          (1..REPS).each do |rep|
            break if stopped
            Eval::Classifier::Stage.open(corpus.positions) do |stages|
              Eval::Concurrency.fan(corpus.lines, threads: concurrency) do |line|
                read_one.call(line, rep, stages.fetch(line.position))
              end
            end
          end
        end
      end
    end
    raise stopped if stopped
    result(journal, corpus: corpus, identity: protocol.fetch("request_identity"), name: set, concurrency: concurrency).write!(directory)
    journal
  end
end

if ENV["PHYSICAL_CLASSIFIER_MODE"] == "run"
  $stdout.sync = true
  PhysicalClassifierStudy.run(directory: ENV.fetch("OUT"), concurrency: Integer(ENV.fetch("CONCURRENCY", "4")))
end
