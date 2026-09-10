# Fixed pending moments for branches absent from the main narrator corpus.
# These are producer calls, not whole turns: attack is already an engine blow,
# and its pending records must exist before asking the narrator to describe it.
# Stage uses the engine's writers with seeded picks; no production prompt,
# schema, engine or seed content changes. The stale main set is the separate
# ta-bench-rebaseline-stale follow-up. Mechanical predicates cover explicit
# placed-fact contradictions only. Broader truthfulness, natural next-beat fit,
# geometry semantics and prose quality remain human-only, nullable labels.
module Eval::Prompt::Branches
  BASELINE = "prompt-branches-2026-09-10".freeze

  def self.capture(corpus = Eval::Prompt.corpus("branches"))
    corpus.cases.sort_by(&:id).group_by(&:shape).transform_values do |cases|
      kase = cases.first
      Eval::Classifier::Stage.open([ corpus.position(kase.position) ],
                                   label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                   roots: Eval::Prompt::WORLD_ROOTS) do |stages|
        stage = Stage.new(kase, stages.fetch(kase.position).playthrough).prepare
        { "request" => Eval::RequestIdentity.request(Scene::Narrator::INSTRUCTIONS, stage.prompt, nil),
          "facts" => stage.facts }
      end
    end.sort.to_h
  end

  def self.identity(capture = self.capture)
    Eval::RequestIdentity.of(capture.transform_values { |row| row.fetch("request") })
  end
end
