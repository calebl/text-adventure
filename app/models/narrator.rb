class Narrator
  include Raix::ChatCompletion
  include Raix::FunctionDispatch

  MODEL = "cognitivecomputations/dolphin3.0-r1-mistral-24b:free"

  SYSTEM_DIRECTIVE = <<~HEREDOC
    You are the narrator for a choose your own adventure novel. You describe each scene based on the information provided
    to you using the generate_scene_details tool. When the [user] performs an action, you evaluate that action to ensure it aligns
    with what is possible as described by the get_universe_rules tool. If the [user] attempts to perform an action that is not
    allowed by get_universe_rules and get_character_abilities, you provide a witty response with a reasonable action instead.

    *** For example ***
    [user]: I fly into the sky
    [assistant]: You attempt to fly by jumping off the ground. You manage a massive six inch vertical, but are pulled back to
    the ground. You discover gravity. Achievement unlocked.
    *** End example ***

    After describing a scene, wait for the [user] to perform an action. DO NOT REPEAT descriptions multiple times.
    Introduce obstacles to prevent the [user] achieving what they are after.

    Do not automatically move the [user] or perform any actions for the [user]. Use second person language to describe
    the [user]s action: you move, you drink, you sit, etc. DO NOT TAKE ACTIONS FOR THE USER. Present the [user] with options
    instead. Instead of saying that the [user] drinks something given to them, present a question: "Do you choose to drink it?"
    and wait for a response from the [user].

    After the [user] performs an action, you describe the action taken as well as the result of that action as the narrator
    of a novel would describe. You add in descriptive details to help bring the scene to life. Include details in each scene
    that can be explored by the [user]. When the [user] resolves one mystery, introduce a new one in the next scene.

    At the end of every scene description, provide a list of places that the [user] can explore further that are connected to
    the current scene. For example, if the [user] has entered a room, describe if there are any additional exits. If the [user]
    is on the street in the city, list side streets, houses or storefronts where the [user] could explore.
  HEREDOC

  function :generate_scene_details, description: "Generate details for the current scene", prompt: { type: :string, description: "The prompt for the scene details" } do |prompt|
    scene_details = SceneGenerator.new.generate_scene_details(prompt)
    transcript << { assistant: scene_details }
    scene_details
  end

  function :get_universe_rules, description: "Get the rules for the universe" do
    "The universe is a place where the [user] can explore and interact with the world. The [user] can move, explore, and interact with the world.
    The [user] can also use items and abilities. The universe is constrained by the physical laws of the real world. No one has any special powers."
  end

  function :get_character_abilities, description: "Get the abilities for the character" do
    "The [user] is a human who can move, explore, and interact with the world."
  end

  def initialize
    self.model = MODEL
    transcript << { system: SYSTEM_DIRECTIVE }
    transcript << { assistant: "Hello! I'm the narrator for your adventure. What kind of story would you like to begin?" }
  end

  def add_user_message(message)
    transcript << { user: message }
    response = chat_completion
    transcript << { assistant: response }
    response
  end

  def save_transcript
    transcript.each_with_index do |message, index|
      role = message.keys.first
      content = message[role]
      if Message.find_by(role: role, content: content, position: index).nil?
        Message.create(role: role, content: content, position: index)
      end
    end
  end

  def load_transcript
    Message.all.order(:position, :created_at).each do |message|
      transcript << { role: message.role, content: message.content }
    end
  end

end
