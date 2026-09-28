# Same run/score/board/compare protocol, but a pending producer moment rather
# than a played turn. Every response and token receipt survives offline; the warm-up
# is also retained because it is a paid call, even though it is not a sample.
# This runner owns its request capture: the ordinary bench captures a turn the
# engine plays, which cannot render these pending moments. Shared scoring
# still uses the parent protocol.
class Eval::Prompt::Branches::Bench < Eval::Prompt::Bench
  def run
    captured = Eval::Prompt::Branches.capture(corpus)
    passes = []
    warmups = []
    arms.each do |arm|
      arm.pinned do
        warmups << warm(arm)
        (1..reps).each { |rep| passes << play(arm, rep) }
      end
    end
    Eval::Prompt::Result.new(
      corpus_size: corpus.size, corpus_digest: Eval::Prompt.digest(corpus),
      request_identity: Eval::Prompt::Branches.identity(captured),
      arms: arms.map(&:id), reps: reps, passes: passes.map(&:stored), warmups: warmups,
      **Eval::Prompt::Version.of(passes)
    )
  end

  private

  def warm(arm)
    reading = read(corpus.cases.first, arm, 0)
    { arm: arm.id, seconds: reading.seconds, error: reading.error,
      input_tokens: reading.input_tokens, output_tokens: reading.output_tokens,
      reading: reading.to_h }
  end

  # A PENDING MOMENT IS STAGED IN A ROLLED-BACK TRANSACTION, not on a copy:
  # nothing is played, so nothing the engine writes has to be read back, and
  # its request is built from the rows the stage wrote.
  def read(kase, arm, rep)
    Eval::Classifier::Stage.open([ corpus.position(kase.position) ],
                                 label: Eval::Prompt::Corpus::STAGE_LABEL, retitle: true,
                                 roots: Eval::Prompt::WORLD_ROOTS, pinned: true) do |stages|
      play_case(kase, stages.fetch(kase.position), arm, rep)
    end
  end

  def play_case(kase, standing, arm, rep)
    stage = Eval::Prompt::Branches::Stage.new(kase, standing.playthrough).prepare
    game = stage.game
    intent = intent_for(kase, standing)
    facts = facts_after(kase, intent, game, game.current_location).merge(stage.facts)
    request = stage.request
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sender = Eval::EngineCalls::Sender.new(game)
    answer = sender.call({ "kind" => "chat", "purpose" => "narration", "system" => request.fetch("system"),
                           "user" => request.fetch("user"), "schema" => nil, "stream" => true })
    raise sender.failure if sender.failure

    receipts = receipts_for(sender.receipts)
    Reading.new(kase: kase, arm: arm.id, rep: rep, story: game.story.title, pass: receipts[:pass],
                text: answer.fetch("content").to_s, facts: facts,
                seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                input_tokens: receipts[:input_tokens], output_tokens: receipts[:output_tokens],
                calls: receipts[:calls], answered_by: receipts[:answered_by], instructions: receipts[:instructions],
                prompt: receipts[:prompt], missing_fields: [], cap_hits: [], error: nil)
  rescue StandardError => error
    Reading.new(kase: kase, arm: arm.id, rep: rep, story: standing.playthrough.story.title, pass: kase.pass,
                text: nil, facts: facts || {}, seconds: nil, input_tokens: 0, output_tokens: 0,
                calls: 0, answered_by: nil, instructions: request&.fetch("system"),
                prompt: request&.fetch("user"), missing_fields: [], cap_hits: [], error: "#{error.class}: #{error.message}")
  end
end
