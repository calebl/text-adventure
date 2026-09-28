# WHAT SOMEBODY SAID UNASKED, HELD ON A STAGED MOMENT, for a bench that measures
# how the narrator renders it.
#
# The engine throws the speech die as a turn plays, so no typed line is sure to
# reach a chosen act. A bench that wants one therefore writes the row the die
# would have written: applied, told by no scene yet, and with the FACT THE
# ENGINE OFFERS for that act (`Playthrough::Requests.speech_choices`), never a
# sentence retyped here. The narrator's request is then the engine's, built
# from the rows, and states it in its "What else happened here" line exactly as
# it states what was said on the line being played.
module Eval::HeldSpeech
  class Unoffered < StandardError; end

  # `act` is a token's head after `speak:` -- `greet`, `warn:here`,
  # `warn:way`, `ask`, `demand`, `dismiss` -- and the first token the engine
  # offers with it is the one said.
  def self.say!(game, who, act, location: game.current_location)
    offered = Playthrough::Requests.speech_choices(game, who, location: location)
    said = offered.find { |row| row.fetch("token") == "speak:#{act}" || row.fetch("token").start_with?("speak:#{act}:") }
    raise Unoffered, "#{who.fullname} is offered no #{act.inspect} in #{location.name}: #{offered.map { |row| row["token"] }.inspect}" unless said

    game.volitions.create!(character: who, location: location, chosen: said.fetch("token"), status: "applied",
                           fact: said.fetch("fact"), serves: "none", round: 1,
                           decided_by: Playthrough::Volition::DECIDED_BY_DIE)
  end
end
