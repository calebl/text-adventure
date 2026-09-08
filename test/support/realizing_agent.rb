require_relative "fake_agent"

# A FAKE THAT ANSWERS A WHOLE REALIZATION AND LEAVES THE RECORDS A REAL ONE
# WOULD LEAVE, which is what makes a runner test a test of the runner and not of
# the fake: `Eval::Realization::Bench` reads both answers, what they were told
# and what they cost off the `chats` and `messages` rows the generator wrote, and
# a double that wrote none would leave every one of those figures nil and prove
# nothing about them.
#
# IT ANSWERS BY SCHEMA, which is how `Location::Generator` itself tells its calls
# apart, and it is the only way to answer a conversation whose SHAPE is what a
# test is about: a building makes one call and a room makes two.
#
# SHARED BY BOTH LABS' RUNNER TESTS, because a draw for `Lab::Exits` IS a draw
# for `Lab::Realization` read from the other end (`Lab::Exits::Runner`). A second
# fake would be a second answer to what a realization call leaves behind, and the
# two could drift into testing different things.
class RealizingAgent < FakeAgent
  DETAIL = {
    "description" => "Black water stands a foot deep over the boards, and the doors have swollen shut.",
    "lore" => "It took fish for forty years and then it took the river."
  }.freeze

  PLACE = DETAIL.merge(
    "parameters" => { "storeys_above" => "ground floor only", "storeys_below" => "a cellar",
                      "danger" => "uneasy", "gradient" => "worse the deeper you go",
                      "hazard" => "flooded" }
  ).freeze

  EXITS = {
    "exits" => [
      { "name" => "The Chandler's Lane", "teaser" => "Rope and tar, and a light still on.",
        "distance" => "a short walk", "travel_method" => "walking",
        "inside" => Location::Parameters::NO_INSIDE, "population" => "a person or two" }
    ]
  }.freeze

  def initialize(answer = nil, purpose: nil, instructions: nil)
    super()
    @answer = answer
    @purpose = purpose
    @instructions = instructions
  end

  def ask(prompt, verify: nil)
    @prompts << prompt
    raise @answer if @answer.is_a?(Exception)

    content = answer_for(@schemas.last)
    write!(prompt, content)
    verify&.call(content)
    Response.new(content)
  end

  def recorded_chat = @chat

  def current_model = { provider: :fake, model: "fake/model" }

  private

  def answer_for(schema)
    return EXITS if schema == Location::ExitsSchema
    return PLACE if schema == Location::PlaceSchema

    DETAIL
  end

  # THE REGISTRY ROW IS ASSOCIATED RATHER THAN THE ID ASSIGNED, which is
  # `test/factories/chats.rb`' rule: assigning `model_id` as a string makes
  # RubyLLM resolve it through the provider, which needs an API key, and this
  # test has none and wants none.
  def write!(prompt, content)
    @chat ||= Chat.create!(purpose: @purpose, model: registry).tap do |chat|
      chat.messages.create!(role: "system", content: @instructions, model: registry) if @instructions
    end
    @chat.messages.create!(role: "user", content: prompt, model: registry)
    @chat.messages.create!(role: "assistant", model: registry, content: content.to_json,
                           content_raw: content, input_tokens: 900, output_tokens: 250)
  end

  def registry
    @registry ||= Model.find_by(model_id: "fake/model") ||
                  FactoryBot.create(:model, model_id: "fake/model", name: "fake/model",
                                            provider: "openrouter")
  end
end
