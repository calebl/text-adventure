# Quest admission is observed BEFORE finish_realization! invokes Deadline.
# A target the engine supplies after a model declines is not model take-up.
# Replay uses the same writers and fixed staged records, with stored structured
# answers standing in only for ask; it never parses prose or calls a provider.
module Eval::Realization::Admissions
  module Capture
    attr_accessor :measured_quest_step
    attr_reader :measured_quest_admission

    def finish_realization!
      # Interior completion may be visited again by the exits phase. The first
      # observation is the one before Deadline, including when it was false.
      if measured_quest_step && !defined?(@measured_quest_admission)
        @measured_quest_admission = measured_quest_step.reload.bound?
      end
      super
    end
  end

  def self.replay(row)
    kase = Eval::Realization.corpus.cases.find { |entry| entry.id == row.fetch("id") }
    raise ArgumentError, "unknown realization case" unless kase

    Eval::Realization::Stage.open([ kase ], label: "admission replay") do |stages|
      generator = stages.fetch(kase.id).generator
      generator.singleton_class.prepend(Capture)
      generator.measured_quest_step = generator.send(:open_step)
      answers = row.fetch("answers")
      generator.define_singleton_method(:ask) do |schema, _prompt|
        answers.fetch(schema == Location::ExitsSchema ? "exits" : "detail")
      end
      generator.realize!
      generator.measured_quest_admission
    end
  end
end
