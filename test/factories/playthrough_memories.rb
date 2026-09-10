FactoryBot.define do
  factory :playthrough_memory, class: "Playthrough::Memory" do
    transient do
      game { build(:playthrough) }
      person { build(:character, story: game.story) }
    end
    initialize_with { new(game, person) }
    skip_create
  end
end
