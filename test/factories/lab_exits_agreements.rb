FactoryBot.define do
  factory :lab_exits_agreement, class: "Lab::Exits::Agreement" do
    transient do
      vantages { [] }
      label { Lab::Exits::Agreement::TUNING }
    end
    initialize_with { new(vantages, label: label) }
  end

  factory :lab_exits_agreement_report, class: "Lab::Exits::Agreement::Report" do
    transient do
      sets { [] }
      io { StringIO.new }
    end
    initialize_with { new(sets, io: io) }
  end
end
