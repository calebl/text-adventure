# Explicitly approved live launch only. Keep the original evaluator/corpus,
# capture actual full Turn responses, and share the existing $4 budget ledger.
require_relative "support"
root = PhysicalConfirmation::ROOT
lock = File.open("/tmp/ta-physical-classifier-revised-20260910-run.lock", File::RDWR | File::CREAT, 0o600)
raise "This physical arm is already active" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
manifest = JSON.parse(root.join("preflight.json").read)
raise "Source changed since inspected preflight" unless PhysicalConfirmation.source == manifest.fetch("source")
raise "Request manifest changed" unless Digest::SHA256.file(root.join("requests.json")).hexdigest == manifest.fetch("requests_sha256")
raise "Exactly four runs required" unless ENV.fetch("REPS", "4") == "4"
raise "Wrong isolated database" unless File.expand_path(ActiveRecord::Base.connection_db_config.database) == PhysicalConfirmation::DATABASE
raise "Wrong shared budget ledger" unless ENV.fetch("EVAL_BUDGET_FILE") == "/tmp/text-adventure-live-eval-20260909/budget.json"
PhysicalConfirmation.empty_database!
samples = JSON.parse(root.join("requests.json").read).fetch("samples")
PhysicalConfirmation.gate = PhysicalConfirmation::Gate.new(samples)
ReviewEvalBudget.install!
prefix = "physical:#{PhysicalConfirmation::LABEL}:"
if ReviewEvalBudget.ledger.snapshot.fetch("entries").any? { |entry| entry.fetch("label").start_with?(prefix) }
  raise "This arm already has a paid attempt; inspect its receipts before any restart"
end
PhysicalConfirmation.install!
ENV["EVAL_BUDGET_HELPER"] = PhysicalConfirmation::HELPER.to_s
ENV["EVAL_PREFLIGHT"] = "0"
ENV["EVAL_SOURCE_SHA"] = manifest.fetch("source_sha256")
ENV["EVAL_ARM"] = PhysicalConfirmation::LABEL
ENV["REPS"] = "4"
ENV["OUT"] = root.join("physical-after.json").to_s
load PhysicalConfirmation::ORIGINAL.join("evaluate.rb")
puts "Completed #{PhysicalConfirmation.gate.sent.length} actual calls through the full turn engine."
