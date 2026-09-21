# This package was bought with `rake eval:realization` / `rake eval:genesis`
# into tmp/eval/desires-scale-20260920, then compacted here. It does not stream
# a second live purchase. EVAL_PREFLIGHT=1 writes only offline identities.
require "json"
require "digest"
require_relative "payload_gate"

module DesiresScaleRun
  extend self

  NAME = "desires-scale-20260920".freeze
  ROOT = Rails.root.join("db/eval", NAME)
  MODEL = "mistralai/mistral-medium-3.1".freeze

  def write_preflight!
    source = JSON.parse(ROOT.join("source-manifest.json").read)
    puts JSON.pretty_generate(offline: true, model_calls: 0,
      prompt_digest: source.fetch("prompt_digest"),
      schema_request_identity: source.fetch("schema_request_identity"),
      branch_request_identity: source.fetch("branch_request_identity"),
      purchase_path: source["purchase_path"])
  end
end

if ENV["EVAL_PREFLIGHT"] == "1"
  DesiresScaleRun.write_preflight!
else
  abort "This package is already recorded. Use rake eval:realization SET=<new> for a fresh purchase, or EVAL_PREFLIGHT=1."
end
