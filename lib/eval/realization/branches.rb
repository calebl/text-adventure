# Fixed record surgery for conditional requests. No producer instruction or
# schema is replaced. Cast slots use a seeded draw from this world's records;
# the ordinary registry still decides the allowance and every admission.
# Geometry is detected here, not scored: wall-specific door prose belongs to
# the geometry lab. Natural quest fit, name quality and readable-word meaning
# likewise cannot be inferred from an admission receipt.
class Eval::Realization::Branches
  attr_reader :standing

  def initialize(standing)
    @standing = standing
  end

  def stage!
    options = standing.kase.staging
    room = standing.location
    Array(options["named_siblings"]).each do |entry|
      sibling = room.parent_location.child_locations.find_by!(name: entry.fetch("room"))
      accepted = Location::RoomName.for(sibling)&.accept(entry.fetch("name"))
      raise Eval::Realization::Stage::Unstageable, "invalid sibling name" unless accepted

      sibling.update!(name: accepted)
    end
    if options["saturated_items"]
      Item::Registry::MAX_PER_ROOM.times do |index|
        standing.generator.registry.admit!([ { "name" => "brass tally #{index + 1}",
                                              "description" => "A small numbered brass tally." } ])
      end
      raise Eval::Realization::Stage::Unstageable, "items did not fill the allowance" unless standing.item_allowance.zero?
    end
    if (wanted = options["quest"])
      quest = standing.story.quests.create!(title: "The missing customs record", premise: "Recover the missing customs record.",
                                            origin: "generated", status: "open", contributes: true)
      quest.outcomes.create!(name: "recovered", summary: "The customs record is recovered.", is_default: true)
      quest.steps.create!(**wanted.symbolize_keys, position: 1)
    end
    room.update!(population: options.fetch("population", "a person or two"))
    seed_cast!
    restore! if options["retry_detail"]
    standing
  end

  def seed_cast!
    room = standing.location
    rng = Roll.generator(story: Zlib.crc32(standing.kase.story), sequence: Zlib.crc32(standing.kase.id), kind: Roll::POPULATION)
    registry = standing.generator.cast_registry
    slots = Array.new(registry.send(:drawn)) do
      monstrous = Location::Danger.monstrous?(room, rng: rng)
      universe = standing.story.universe
      pool = monstrous ? universe.monstrous_races : universe.peoples
      race = (pool.presence || universe.races).sort_by(&:name).sample(random: rng)
      { race: race, age: rng.rand(18..80), sex: Character.sexes.values.sample(random: rng) }
    end
    standing.generator.instance_variable_set(:@cast_registry, Character::Registry.new(room, slots: slots))
  end

  # This accepted fixture is applied by the engine's checkpoint path. No chat
  # remains, so Generator#agent must restore the exchange via add_message.
  def restore!
    generator = standing.generator
    detail = standing.kase.staging.fetch("retry_detail")
    standing.location.update!(generation_checkpoint: {
      "phase" => Location::Generator::DETAIL_PENDING, "prompt" => generator.detail_prompt,
      "detail" => detail, "slots" => generator.cast_registry.slots.map { |slot|
        { "race_id" => slot.fetch(:race).id, "age" => slot.fetch(:age), "sex" => slot.fetch(:sex) }
      }
    })
    generator.write_detail!
  end
end
