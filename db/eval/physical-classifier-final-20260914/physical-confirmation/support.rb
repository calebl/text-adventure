# Reuse the prior fixture gate verbatim, changing only this runner's artifact,
# database and ledger namespace. No prior package or engine source is edited.
require Rails.root.join("db/eval/physical-classifier-revised-20260910/physical-confirmation/support")

module FinalPhysicalConfirmation
  ROOT = Rails.root.join("db/eval/physical-classifier-final-20260914/physical-confirmation")
  SHARED = Rails.root.join("db/eval/physical-classifier-revised-20260910/physical-confirmation")
  DATABASE = "/tmp/ta-physical-classifier-final-20260915-live.sqlite3".freeze
  LABEL = "classifier-final-20260915".freeze
  LEDGER = "/tmp/text-adventure-live-eval-20260909/budget.json".freeze

  # The shared module resolves these constants when called. Its request checks,
  # sequence offsets, corpus, full Turn path and effect binding remain identical.
  { ROOT: ROOT, DATABASE: DATABASE, LABEL: LABEL }.each do |name, value|
    PhysicalConfirmation.send(:remove_const, name)
    PhysicalConfirmation.const_set(name, value)
  end

  module SharedSource
    def source
      names = %w[support.rb gate_check.rb].map { |name| FinalPhysicalConfirmation::SHARED.join(name).relative_path_from(Rails.root).to_s }
      super.merge(names.to_h { |name| [ name, Digest::SHA256.file(Rails.root.join(name)).hexdigest ] }).sort.to_h
    end
  end
  PhysicalConfirmation.singleton_class.prepend(SharedSource)
end
