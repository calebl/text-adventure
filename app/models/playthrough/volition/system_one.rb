# Typed System One overlay for the deterministic volition floor. Every answer is
# checked against the current records before it can affect the game.
#
# THE REQUEST STATES WHAT IT ASKS ABOUT. The state is
# `Playthrough::Volition::State` -- the room, each person by name with their
# desires and what they witnessed, and the player's line -- so each question
# below is answerable from what was sent. The acts are that state's labelled
# criteria, and an answer is mapped back to a token through it.
#
# A FAILURE LEAVES A RECEIPT AND NEVER BLOCKS A TURN. Every way the call can
# fail ends at the die, as before; what changed is that it is no longer
# silent. `#decisions` hands back the failure with the (empty) decisions, and
# `Playthrough::Volition.run!` writes it onto every row the die then decides
# (`playthrough_volitions.decided_by` / `system_one_error`), beside a log line.
class Playthrough::Volition::SystemOne
  PRESSURE_THRESHOLD = 0.5
  SERVES = Playthrough::Volition::SERVES.freeze

  PRESSURE =
    "How strongly is this person pressured toward what they will not face?".freeze

  # `acts` is character id => token for every person whose typed act replaces
  # the die; `failure` is nil, or a one-line reason the call did not answer.
  Outcome = Data.define(:acts, :failure) do
    def asked? = !acts.nil? || !failure.nil?
  end

  NOT_ASKED = Outcome.new(acts: nil, failure: nil)

  def initialize(playthrough, characters, location:, line: nil, agent: nil)
    @playthrough, @characters, @location, @line = playthrough, characters, location, line
    @agent = agent
  end

  def state = @state ||= Playthrough::Volition::State.new(@playthrough, @characters, location: @location, line: @line)

  def request = { state: state.to_h, questions: questions }

  def questions
    state.people.each_with_object({}) do |person, asked|
      asked["#{person.key}:act"] = choice(state.criteria_for(person))
      asked["#{person.key}:serves"] = choice(SERVES.index_with(&:itself))
      asked["#{person.key}:pressure"] = { "type" => "noul", "instructions" => PRESSURE, "criteria" => {} }
    end
  end

  def decisions
    return NOT_ASKED unless @characters.any? && (@agent || SystemOneAgent.configured?)

    answers = agent.ask_questions(**request)
    acts = state.people.each_with_object({}) do |person, result|
      next unless answers.noul("#{person.key}:pressure") >= PRESSURE_THRESHOLD

      token = state.token_for(person, answers.choice("#{person.key}:act"))
      result[person.character.id] = token if token
    end
    Outcome.new(acts: acts, failure: nil)
  rescue SystemOneAgent::Unavailable, Timeout::Error => e
    Rails.logger.warn { "[system_one] volition #{e.class}: #{e.message} -- the die decides this room" }
    Outcome.new(acts: nil, failure: "#{e.class}: #{e.message}".truncate(255))
  end

  private

  def agent = @agent ||= SystemOneAgent.new(purpose: "volition")

  def choice(criteria)
    { "type" => "choice", "instructions" => "Choose one option.", "criteria" => criteria }
  end
end
