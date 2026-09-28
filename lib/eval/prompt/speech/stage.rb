# One held speech row, or two, inside Classifier::Stage's rollback boundary.
# The speaker is the first person in the room with a pursuit, and what they
# say is the first thing of its kind the engine offers them; the fact is the
# engine's. `beside_an_act` holds an act of theirs first, written by
# `Playthrough::Volition`, so the prompt states both in id order.
class Eval::Prompt::Speech::Stage
  # What each shape has the speaker say, as the head of the engine's token.
  SAID = { "greet" => "greet", "warn_here" => "warn:here", "warn_way" => "warn:way", "ask" => "ask",
           "demand" => "demand", "dismiss" => "dismiss", "beside_an_act" => "dismiss" }.freeze

  attr_reader :kase, :game, :fact

  def initialize(kase, game)
    @kase, @game = kase, game
    @fact = nil
  end

  def prepare
    act = SAID.fetch(kase.shape) { raise ArgumentError, "unknown speech shape #{kase.shape.inspect}" }
    walk_off_with_something! if kase.shape == "beside_an_act"
    @said = Eval::HeldSpeech.say!(game, speaker, act)
    game.reload
    self
  end

  # THE NARRATOR'S REQUEST FOR THE STAGED MOMENT, the engine's: `{system, user}`.
  def request = @request ||= Playthrough::Requests.narration(game, command: kase.typed)
  def prompt = request.fetch("user")

  def facts
    { "speech" => { "speaker" => speaker.fullname, "nickname" => speaker.nickname, "token" => @said.chosen,
                    "fact" => @said.fact },
      "acts" => game.volitions.untold.chronological.map(&:fact) }
  end

  private

  def speaker
    @speaker ||= game.story.characters.where(location: game.current_location).where.not(desire_pursuit: nil)
                     .where.not(id: game.character.id).order(:id).first or
      raise ArgumentError, "#{kase.id}: nobody in #{game.current_location.name} has a pursuit to speak from"
  end

  # The first thing on the floor the speaker may pick up, as `Playthrough::Volition` offers it.
  def walk_off_with_something!
    volition = Playthrough::Volition.new(game, speaker, location: game.current_location)
    take = volition.choices.keys.find { |token| token.start_with?("take:") } or
      raise ArgumentError, "#{kase.id}: nothing lies in #{game.current_location.name} that #{speaker.fullname} may take"
    volition.apply!(take)
  end
end
