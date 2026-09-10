# ONE ROLLED-BACK WORLD, WITH FIXED UPSTREAM FACTS AT EACH BOUNDARY.
# The chain is deliberately reset between producers: buying a fresh universe
# for every character would measure different inputs, not prompt differences.
# Society and the duplicate retry replay the fixed preceding exchange through
# BaseAgent#add_message; neither replay buys a call.
#
# The old generators use Array#sample and Kernel#rand. The bench seeds their
# constructor only, through Roll.seed, and fixes the body's world identity
# through StatBlock.roll. No process-global random setting spans a model call.
# Database-issued ids must not choose the measured person's body.
class Eval::Genesis::Stage
  Request = Data.define(:call, :system, :user, :schema, :history, :facts) do
    def identity
      { "system" => system, "user" => user, "schema" => JSON.parse(JSON.generate(schema.new.to_json_schema)),
        "history" => history }
    end
  end

  attr_reader :kase, :story, :document

  def self.open(kase)
    Eval::Concurrency.rolled_back { yield new(kase).stand! }
  end

  def initialize(kase)
    @kase = kase
    @document = WorldSeed.parse(File.read(Eval::Genesis::WORLD))
  end

  def stand!
    @story = Eval::Realization::Stage.load_world!(document.fetch("story").fetch("title"),
      title: "genesis bench #{kase.id}", whose: "genesis: ")
    @fixed_character = story.protagonist || story.characters.order(:id).first
    @sheet = @fixed_character.attributes.slice(*Character::Schema.required_properties.map(&:to_s))
    @opening = story.opening_location
    # Only the first stub and the fixed player exist at the quest boundary.
    story.quests.destroy_all
    story.scenes.destroy_all
    story.items.destroy_all if story.respond_to?(:items)
    story.locations.where.not(id: @opening.id).destroy_all
    @opening.update!(description: nil, lore: nil, detail_level: :stub)
    fixed_player = @fixed_character.dup
    story.characters.destroy_all unless kase.producer == "retry"
    @taken_names = story.characters.pluck(:fullname)
    @character = seeded { Character::Generator.new(story, protagonist: true) }
    roll_context = Struct.new(:id, :clock).new(kase.seed, story.clock)
    @body = Character::StatBlock.for_a_protagonist(roll_context)
    body = @body
    @character.define_singleton_method(:body_for) { |_story| body }
    fixed_player.save! if kase.producer.in?(%w[first_screen quest])
    @universe = seeded { Universe::Generator.new(premise: premise) }
    self
  end

  def seeded
    previous = srand(Roll.seed(story: kase.seed))
    yield
  ensure
    srand(previous)
  end

  def premise = "A knight enters the goblin caves beneath the Ashen Spire to recover the captured prince."

  def request(call, generator, user, schema, history: [], facts: {})
    Request.new(call: call, system: generator.system_prompt, user: user, schema: schema,
                history: history, facts: facts)
  end

  def requests
    case kase.producer
    when "first_screen" then [ story_request, character_request, quest_request ]
    when "universe" then universe_requests
    when "story" then [ story_request ]
    when "character" then [ character_request ]
    when "retry" then [ character_request(retry_name: true) ]
    when "quest" then [ quest_request ]
    end
  end

  def universe_requests
    physical = document.fetch("universe").slice(*Universe::PhysicalSchema.required_properties.map(&:to_s))
    [ request("physical", @universe, @universe.physical_prompt, Universe::PhysicalSchema),
      request("societal", @universe, @universe.societal_prompt, Universe::SocietalSchema,
        history: [ { "role" => "user", "content" => @universe.physical_prompt },
                   { "role" => "assistant", "content" => physical } ]) ]
  end

  def story_request
    generator = Story::Generator.new(story.universe, premise: premise)
    request("story", generator, generator.generation_prompt, Story::Schema)
  end

  def character_request(retry_name: false)
    prompt = @character.instance_variable_get(:@character_generation_prompt)
    facts = { "body" => @body.stringify_keys, "race" => @character.race.name,
              "races" => story.universe.races.pluck(:name), "age" => @character.age, "sex" => @character.sex,
              "hostile" => Character.hostile_by_default?(@character.race),
              "taken_names" => @taken_names }
    history = []
    if retry_name
      history = [ { "role" => "user", "content" => prompt }, { "role" => "assistant", "content" => @sheet } ]
      prompt = @character.retry_prompt(@sheet.fetch("fullname"))
      facts["retry_name"] = @sheet.fetch("fullname")
    end
    request(retry_name ? "retry" : "character", @character, prompt, Character::Schema, history: history, facts: facts)
  end

  def quest_request
    generator = Quest::Generator.new(story)
    request("quest", generator, generator.generation_prompt, Quest::Schema,
      facts: { "step_bounds" => [ Quest::Schema::STEPS.first, Quest::Schema::STEPS.last ],
               "outcome_bounds" => [ Quest::Schema::OUTCOMES.first, Quest::Schema::OUTCOMES.last ],
               "triggers" => Quest::Schema::TRIGGERS })
  end

  # The character is the generator's unsaved sheet, not a second protagonist
  # persisted beside the fixed upstream player. Its model validity in that
  # artificial coexistence is not an admission score.
  # Feed the answer to the production admission path. No new request is made:
  # quest's private ask is replaced on this one generator, not on BaseAgent.
  def apply(request, answer)
    case request.call
    when "character", "retry"
      character = @character.send(:build_from, answer)
      { "body" => character.attributes.slice(*@body.keys.map(&:to_s)), "race" => character.race.name,
        "age" => character.age, "sex" => character.sex, "hostile" => character.hostile,
        "fullname" => character.fullname }
    when "quest"
      generator = Quest::Generator.new(story)
      generator.define_singleton_method(:ask) { answer }
      quest = generator.generate!
      return { "admitted" => false } unless quest

      { "admitted" => true, "steps" => quest.steps.map { |step| step.attributes.slice("position", "target_id", "trigger_kind") },
        "outcomes" => quest.outcomes.map { |outcome| outcome.attributes.slice("name", "is_default") } }
    else {}
    end
  end
end
