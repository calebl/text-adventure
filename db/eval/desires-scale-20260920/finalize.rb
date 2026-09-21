# Finalize is a no-op for this package: receipts, comparisons and provenance
# were written when the rake eval:realization candidate was compacted into
# db/eval/desires-scale-20260920. Re-running finalize does not buy calls.
require "json"

module DesiresScaleFinalize
  extend self

  ROOT = Pathname.new(__dir__)

  def run
    required = %w[realization.json readings.json.gz receipts.json requests.json
                  source-manifest.json run-provenance.json comparison.txt verdicts.json]
    missing = required.reject { |name| ROOT.join(name).exist? }
    raise "Package incomplete: #{missing.join(", ")}" if missing.any?
    puts JSON.pretty_generate(ok: true, package: ROOT.basename.to_s,
      actual_usd: JSON.parse(ROOT.join("receipts.json").read).fetch("current_actual"))
  end
end

DesiresScaleFinalize.run
