# MOMENTS THE GAME ITSELF REACHED: a sweep script from
# `lib/engine_sweep/scripts/` played offline through `EngineSweep::Walk`'s own
# pieces (the world loaded from its seed file, and each line run through
# `Playthrough::Mechanics` with `model: false`), stopping after chosen steps.
#
# IDS START AT 1, NOT AT `EngineSweep::Walk::ID_BASE`. The walk's own pin
# writes the start into `sqlite_sequence`, which an in-memory database (the
# rake task's) does not honour, so the same walk would get other ids -- and
# roll other dice -- there than in the suite's database. Every counter is
# reset to zero instead (`EngineVectors::Records.frozen`), which both honour.
# NO MODEL IS ASKED ANYTHING: each line is run inside
# `EngineSweep.without_a_model`, which also turns the System One switch off,
# so a shell holding a provider key walks the same game as one without.
#
# So a moment here is the engine's own, but not the moment the sweep script
# itself asserts on.
#
# So the blows, the tolls, the volitions and the vitals a builder reads were
# written by the engine's own statements rather than by hand, and a case's
# input is every row the database holds at that step (`EngineVectors::Records`).
module EngineVectors::Walked
  SCRIPTS = "lib/engine_sweep/scripts".freeze
  TOKEN = EngineVectors::Records::FIXED

  # Yields (playthrough, step index, step) after each step whose index is in
  # `stops`, inside one rolled-back transaction with the clock stopped. The
  # first player's steps only; a script's re-seed and browser steps are
  # skipped rather than played.
  def self.each_stop(script_name, stops)
    script = EngineSweep::Script.load(Rails.root.join(SCRIPTS, "#{script_name}.yml"))
    results = []
    EngineVectors::Records.frozen do
      walk = EngineSweep::Walk.new(script)
      walk.send(:load_world!)
      story = Story.find_by!(title: "#{script.story}#{EngineSweep::Walk::TITLE_SUFFIX}")
      game = walk.send(:playthrough_for, story)
      # The token is random at birth and read by nothing here.
      game.update_column(:token, TOKEN)
      engine = walk.send(:engine_for, game)
      player = script.steps.first.player
      script.steps.each_with_index do |step, index|
        next if step.reseed? || step.browser || step.player != player

        EngineSweep.without_a_model { engine.with_choice(step.npc_action) { engine.run(step.typed) } }
        results << yield(game.reload, index, step) if stops.include?(index)
      end
    end
    results
  end
end
