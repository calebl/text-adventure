# Typed System One overlay for the deterministic volition floor. Every answer is
# checked against the current records before it can affect the game.
class Playthrough::Volition::SystemOne
  PRESSURE_THRESHOLD = 0.5
  SERVES = Playthrough::Volition::SERVES.freeze

  def initialize(playthrough, characters, location:)
    @playthrough, @characters, @location = playthrough, characters, location
  end

  def decisions
    return nil unless SystemOneAgent.configured? && @characters.any?

    questions = {}
    @characters.each do |character|
      prefix = character.id.to_s
      tokens = Playthrough::Volition.new(@playthrough, character, location: @location).choices.keys
      questions["#{prefix}:act"] = choice(tokens)
      questions["#{prefix}:serves"] = choice(SERVES)
      questions["#{prefix}:pressure"] = {
        "type" => "noul",
        "instructions" => "How strongly is this person pressured toward what they will not face?",
        "criteria" => {}
      }
    end
    answers = SystemOneAgent.new(purpose: "volition").ask_questions(
      state: { "location" => @location.id, "characters" => @characters.map(&:id) }, questions: questions
    )
    @characters.each_with_object({}) do |character, result|
      prefix = character.id.to_s
      next unless answers.noul("#{prefix}:pressure") >= PRESSURE_THRESHOLD
      result[character.id] = answers.choice("#{prefix}:act")
    end
  rescue SystemOneAgent::Unavailable, SystemOneAgent::UnusableAnswerError, Timeout::Error
    nil
  end

  private

  def choice(options)
    { "type" => "choice", "instructions" => "Choose one option.",
      "criteria" => options.index_with { |option| option.to_s } }
  end
end
