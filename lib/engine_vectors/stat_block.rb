# `Character::StatBlock`: the level, hit die and three abilities a body is born with.
module EngineVectors::StatBlock
  SOURCES = [ "app/models/character/stat_block.rb", "app/models/character.rb", "app/models/roll.rb" ].freeze
  NOTES = "Each case is Character::StatBlock.roll(story:, at:, sequence:), which is also what for_new " \
          "(at = the story clock in seconds) and for_existing (at = 0, sequence = the character id) " \
          "call. A protagonist case is for_a_protagonist: the same roll with level and hit_die replaced.".freeze

  Story = Struct.new(:id, :clock)

  def self.constants_table
    {
      "hit_dice" => Character::HIT_DICE,
      "abilities" => Character::ABILITIES.map(&:to_s),
      "starting_level" => Character::StatBlock::STARTING_LEVEL,
      "protagonist_level" => Character::StatBlock::PROTAGONIST_LEVEL,
      "protagonist_hit_die" => Character::StatBlock::PROTAGONIST_HIT_DIE,
      "ability_dice" => Character::StatBlock::ABILITY_DICE,
      "ability_sides" => Character::StatBlock::ABILITY_SIDES
    }
  end

  def self.cases
    rolls = [ 1, 2, 7, 42, 999 ].product([ 0, 1_767_225_600 ], (0...30).to_a).map do |story, at, sequence|
      input = { "story" => story, "at" => at, "sequence" => sequence }
      EngineVectors.case_for("roll #{story}/#{at}/#{sequence}", input.merge("protagonist" => false),
                             plain(Character::StatBlock.roll(story: story, at: at, sequence: sequence)))
    end
    protagonists = (1..20).map do |story|
      at = 1_767_225_600 + story * 60
      input = { "story" => story, "at" => at, "sequence" => story % 4, "protagonist" => true }
      EngineVectors.case_for("protagonist #{story}", input,
                             plain(Character::StatBlock.for_a_protagonist(Story.new(story, Time.at(at).utc), sequence: story % 4)))
    end
    rolls + protagonists
  end

  def self.plain(block) = block.transform_keys(&:to_s)
end
