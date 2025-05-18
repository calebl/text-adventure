class SceneGenerator
  include Raix::ChatCompletion

  attr_accessor :model

  def initialize
    self.model = "cognitivecomputations/dolphin3.0-r1-mistral-24b:free"
  end

  def generate_scene_details(prompt)
    format = Raix::ResponseFormat.new("SceneDetails", {
      scene_title: { type: "string" },
      scene_description: { type: "string" }
    })

    self.chat_completion(prompt, format: format)
  end
end