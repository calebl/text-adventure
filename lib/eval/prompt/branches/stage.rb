# Rebuild the moment from records inside Classifier::Stage's rollback boundary.
# Seeded dice are explicit inputs here, independent of database IDs. Ordinary
# swings draw one body die through damage_for; a heavy throw draws its own die
# through throw_item!. No copied prompt sentences and no generated setup prose.
class Eval::Prompt::Branches::Stage
  attr_reader :kase, :game, :fact

  def initialize(kase, game)
    @kase, @game = kase, game
    @turn = Playthrough::Turn.new(game)
    @rng = Random.new(41)
  end

  def prepare
    case kase.shape
    when "combat" then combat
    when "toll", "saved_toll" then toll
    when "throw" then throw_heavy
    when "recap" then history
    when "wounded" then @turn.harm!(game.character, 3)
    when "dead_foe" then dead_foe
    when "next_beat", "plan" then nil
    else raise ArgumentError, "unknown narrator branch #{kase.shape.inspect}"
    end
    game.reload
    self
  end

  def narrator = @narrator ||= Scene::Narrator.new(game)
  def prompt = narrator.send(:prompt_for, kase.typed, fact)
  def narrate = narrator.narrate(kase.typed, fact: fact)

  def facts
    quest = game.story.main_quest
    next_step = Playthrough::Arc.new(game).next_step
    { "branch" => kase.shape,
      "bodies" => ([ game.character ] + game.story.characters.where(location: game.current_location).to_a).uniq.filter_map { |person|
        state = game.vitals_for(person)
        { "name" => person.fullname, "player" => person == game.character, "hp" => state.hp, "max" => state.max } if state
      },
      "blows" => game.blows.open.chronological.map { |blow|
        { "attacker" => blow.attacker.fullname, "target" => blow.target.fullname,
          "damage" => blow.damage, "hp_after" => blow.hp_after, "round" => blow.round,
          "die" => (@thrown && blow.attacker == game.character ? @thrown.item.thrown_die : blow.attacker.hit_die) }
      },
      "tolls" => game.tolls.untold.chronological.map { |row|
        { "name" => row.character.fullname, "where" => row.where_it_was,
          "damage" => row.damage, "hp_after" => row.hp_after, "saved" => row.saved? }
      },
      "throw" => (@thrown && { "item" => @thrown.item.name, "target" => @thrown.target.fullname,
                              "kind" => @thrown.kind.to_s, "die" => @thrown.item.thrown_die }),
      "next_beat" => next_step&.summary,
      "withheld" => (quest ? quest.steps.where.not(id: next_step&.id).pluck(:summary) + quest.outcomes.pluck(:summary) : []),
      "recap" => game.recap, "plan" => Location::Plan.for(game.current_location)&.to_prompt }
  end

  private

  def foe = game.story.characters.find_by!(fullname: "Gorva the Wanderer")

  def swing(attacker, target, round:)
    @turn.strike!(attacker, target, round: round, damage: @turn.damage_for(attacker, rng: @rng))
  end

  def combat
    swing(game.character, foe, round: 1)
    swing(foe, game.character, round: 1)
  end

  def dead_foe
    @turn.harm!(foe, foe.max_hp - 1)
    swing(game.character, foe, round: 1)
  end

  def toll
    saved = kase.shape == "saved_toll"
    damage = saved ? 0 : Roll.die(4, rng: @rng)
    after = @turn.harm!(game.character, damage)
    game.tolls.create!(character: game.character, location: game.current_location,
                       hazard: "unlit",
                       saved: saved, damage: damage, hp_after: after.hp, sequence: -1,
                       story_timestamp: game.story_now)
  end

  def throw_heavy
    item = game.items.create!(name: "stone weight", description: "A heavy stone with a handhold.",
                              bulk: "heavy", location: game.current_location)
    @turn.carry!(item)
    # The successful pick is frozen, not retried until a convenient result.
    @thrown = @turn.throw_item!(item, at: foe, round: 1, rng: Random.new(1))
    raise "the designated heavy throw must strike" unless @thrown.struck?

    @fact = @turn.thrown_fact(@thrown, game.character)
  end

  def history
    previous = game.current_scene
    [ "You inspect the ring in the mud without lifting it.", "You listen to the gate creak overhead." ].each do |words|
      previous = game.story.scenes.create!(location: game.current_location, previous_scene: previous,
                                           description: words, summary: words,
                                           story_timestamp: previous.story_timestamp + 1.minute)
    end
    game.update!(current_scene: previous)
  end
end
