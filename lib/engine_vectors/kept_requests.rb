# REQUESTS A KEPT EVALUATION SET PAID FOR, rebuilt by today's builders from
# the rows they were built from. Each is a literal request stored under
# `db/eval/` beside the answer it bought, and the kept-set tests already
# rebuild them offline; this portion writes a sample down with the records
# the builder read, so a second implementation can reproduce the same bytes.
module EngineVectors::KeptRequests
  SOURCES = [ "lib/eval/arrival/stage.rb", "lib/eval/realization/branch_requests.rb", "lib/eval/realization/stage.rb",
              "lib/eval/dialogue/bench.rb", "lib/eval/dialogue/stage.rb", "lib/eval/dialogue/version.rb",
              "app/models/scene/generator.rb", "app/models/location/generator.rb", "app/agents/InteractionAgent.rb" ].freeze
  NOTES = "Each case is one request from a kept set (`set`, the directory under db/eval; `id` the case, " \
          "`call` which of its calls, from 0) and `records`, every row the database held when the request " \
          "was built (see lib/engine_vectors/records.rb; these stages write their own ids, some negative). " \
          "The output is the request as the set stores it -- {system, user, schema, history}, schema a " \
          "to_json_schema output or null and history the replayed conversation -- and the export stops " \
          "if today's builders do not reproduce the stored bytes. `arrival` is every case of the arrival " \
          "set, `realization` every branch case of the realization bench's current baseline, `dialogue` both calls " \
          "of the first repetition of the first `dialogue_cases` cases, the second built after the " \
          "stored first answer.".freeze

  ARRIVAL = "arrival-branches".freeze
  # The realization set whose requests today's builders send: the bench's
  # current baseline, which superseded the physical-realization set of
  # 2026-09-10 when the generator's prompt moved on.
  REALIZATION = Eval::Realization::BASELINE
  DIALOGUE_CASES = 3

  def self.constants_table = { "dialogue_cases" => DIALOGUE_CASES }

  def self.cases
    arrival + realization + dialogue
  end

  def self.arrival
    stored = JSON.parse(Eval.kept_root.join(ARRIVAL, Eval::Arrival::RESULTS).read).fetch("rows")
    Eval::Arrival.cases.map do |kase|
      row = stored.find { |one| one.fetch("id") == kase.fetch("id") && one.fetch("rep") == 1 }
      EngineVectors::Records.frozen do
        Eval::Arrival::Stage.open(kase) do |stage|
          kept_case(ARRIVAL, kase.fetch("id"), 0, stage.request, row.fetch("requests").first)
        end
      end
    end
  end

  def self.realization
    stored = JSON.parse(Eval.kept_root.join(REALIZATION, "requests.json").read).fetch("requests")
    cases = []
    EngineVectors::Records.frozen do
      Eval::Realization::BranchRequests.offline do |kase, request|
        cases << kept_case(REALIZATION, kase.id, 0, request, stored.fetch(kase.id))
      end
    end
    cases
  end

  def self.dialogue
    stored = Eval::Dialogue::Result.load(Eval.kept_root.join(Eval::Dialogue::BASELINE)).rows
    Eval::Dialogue.cases.first(DIALOGUE_CASES).flat_map do |kase|
      row = stored.find { |one| one.fetch("id") == kase.fetch("id") && one.fetch("rep") == 1 }
      built = []
      EngineVectors::Records.frozen do
        Capture.around(->(request) { built << [ request, EngineVectors::Records.dump ] }) { Eval::Dialogue::Version.rebuild(row) }
      end
      built.each_with_index.map do |(request, records), call|
        kept_case(Eval::Dialogue::BASELINE, kase.fetch("id"), call, request, row.fetch("requests").fetch(call), records)
      end
    end
  end

  def self.kept_case(set, id, call, built, stored, records = EngineVectors::Records.dump)
    request = JSON.parse(JSON.generate(built))
    raise "#{set} #{id} call #{call} no longer reproduces the stored request" unless JSON.generate(request) == JSON.generate(stored)

    EngineVectors.case_for("#{set} #{id} #{call}", { "set" => set, "id" => id, "call" => call, "records" => records }, request)
  end

  # Hands each dialogue request to a callback at the moment it is built, while
  # the rows it was built from are still the rows the database holds.
  module Capture
    KEY = :engine_vectors_dialogue_request

    def self.around(callback)
      Eval::Dialogue::Version.singleton_class.prepend(Capture) unless Eval::Dialogue::Version.singleton_class.include?(Capture)
      previous = Thread.current[KEY]
      Thread.current[KEY] = callback
      yield
    ensure
      Thread.current[KEY] = previous
    end

    def request(agent, prompt)
      super.tap { |built| Thread.current[KEY]&.call(built) }
    end
  end
end
