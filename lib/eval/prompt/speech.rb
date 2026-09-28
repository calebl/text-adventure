# WHAT SOMEBODY SAID UNASKED, TOLD BY THE NARRATOR: the speech corpus's cases.
#
# The engine throws a speech die before the paragraph (its
# `data/playthrough/volition/speech.yml`), and the paragraph is told the fact
# through the "What else happened here" line it already has: greeted, warned,
# asked for, demanded, told to leave, and "Nothing changed hands." / "Nobody
# moved." where the act names a thing or a place. No narrator instruction
# changed for it, so what this measures is whether the prose renders the fact
# and adds no transfer and no second speaker -- the owner's plan says a line is
# added to the instructions only if these cases show one.
#
# A PENDING MOMENT, AS A BRANCH IS (`Eval::Prompt::Branches`): nothing is
# played, because no typed line is sure to reach a chosen die face. The stage
# holds the row the die would have written (`Eval::HeldSpeech`), with the
# engine's own fact, and the narrator's request is the engine's, built from
# the rows. Its own file, so neither `main` nor `branches` loses its kept set.
module Eval::Prompt::Speech
  BASELINE = "prompt-speech-2026-09-28".freeze

  def self.capture(corpus = Eval::Prompt.corpus("speech"))
    corpus.cases.sort_by(&:id).group_by(&:shape).transform_values do |cases|
      kase = cases.first
      Eval::Classifier::Stage.open([ corpus.position(kase.position) ],
                                   label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                   roots: Eval::Prompt::WORLD_ROOTS, pinned: true) do |stages|
        stage = Stage.new(kase, stages.fetch(kase.position).playthrough).prepare
        { "request" => Eval::RequestIdentity.request(stage.request.fetch("system"), stage.prompt, nil),
          "facts" => stage.facts }
      end
    end.sort.to_h
  end

  def self.identity(capture = self.capture)
    Eval::RequestIdentity.of(capture.transform_values { |row| row.fetch("request") })
  end
end
