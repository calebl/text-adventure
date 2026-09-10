FactoryBot.define do
  factory :playthrough_command_journal, class: "Playthrough::Command::Journal" do
    transient do
      submission { build(:playthrough_command) }
    end
    initialize_with { new(submission) }
    skip_create
  end
end
