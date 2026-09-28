# REQUESTS A KEPT EVALUATION SET PAID FOR, rebuilt by today's builders from
# the rows they were built from. Each is a literal request stored under
# `db/eval/` beside the answer it bought, and the kept-set tests already
# rebuild them offline; this portion writes a sample down with the records
# the builder read, so a second implementation can reproduce the same bytes.
#
# THE ARRIVAL AND THE ROOM WRITER'S, whose Ruby builders still write a
# world's rooms and its opening arrival (`Scene::Generator`,
# `Location::Generator`). The dialogue bench's cases were here too; the
# character pass and its narration have no Ruby builder any more, so they are
# the engine's `dialogue_requests` portion.
module EngineVectors::KeptRequests
  SOURCES = [ "lib/eval/arrival/stage.rb", "lib/eval/realization/branch_requests.rb", "lib/eval/realization/stage.rb",
              "app/models/scene/generator.rb", "app/models/location/generator.rb" ].freeze
  NOTES = "Each case is one request from a kept set (`set`, the directory under db/eval; `id` the case, " \
          "`call` which of its calls, from 0) and `records`, every row the database held when the request " \
          "was built (see lib/engine_vectors/records.rb; these stages write their own ids, some negative). " \
          "The output is the request as the set stores it -- {system, user, schema, history}, schema a " \
          "to_json_schema output or null and history the replayed conversation -- and the export stops " \
          "if today's builders do not reproduce the stored bytes. `arrival` is every case of the arrival " \
          "set, and `realization` every branch case of the realization bench's current baseline.".freeze

  ARRIVAL = Eval::Arrival::BASELINE.basename.to_s.freeze
  # The realization set whose requests today's builders send: the bench's
  # current baseline, which superseded the physical-realization set of
  # 2026-09-10 when the generator's prompt moved on.
  REALIZATION = Eval::Realization::BASELINE
  def self.constants_table = {}

  def self.cases
    arrival + realization
  end

  def self.arrival
    stored = JSON.parse(Eval.kept_root.join(ARRIVAL, Eval::Arrival::RESULTS).read).fetch("rows")
    Eval::Arrival.cases.map do |kase|
      row = stored.find { |one| one.fetch("id") == kase.fetch("id") && one.fetch("rep") == 1 }
      EngineVectors::Records.frozen do
        Eval::Arrival::Stage.open(kase) do |stage|
          kept_case(ARRIVAL, kase.fetch("id"), 0, stage.generator_request, row.fetch("requests").first)
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

  def self.kept_case(set, id, call, built, stored, records = EngineVectors::Records.dump)
    request = JSON.parse(JSON.generate(built))
    raise "#{set} #{id} call #{call} no longer reproduces the stored request" unless JSON.generate(request) == JSON.generate(stored)

    EngineVectors.case_for("#{set} #{id} #{call}", { "set" => set, "id" => id, "call" => call, "records" => records }, request)
  end
end
