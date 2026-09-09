require "factory_bot_rails"
require "minitest/mock"
require Rails.root.join("test/support/fake_agent")
FactoryBot.find_definitions if FactoryBot.factories.count.zero?
ActiveRecord::Base.logger = nil
Rails.logger = Logger.new(File::NULL)
DETAIL = { "description" => "A plain workshop with a closed bench.", "lore" => "Tools have been kept here for years.", "items" => [], "people" => [] }.freeze
GOOD = { "name" => "Back Lane", "teaser" => "A lane behind the workshop.", "distance" => "adjacent", "travel_method" => "walking" }.freeze
BAD = GOOD.merge("travel_method" => "teleporting").freeze

def pair(left, right)
  FactoryBot.create(:location_connection, location: left, connected_location: right)
  FactoryBot.create(:location_connection, location: right, connected_location: left)
end

%w[already_has_exit complete_existing_pair duplicate_new_alias capacity_reached natural_key_self forced_invalid forced_valid half_pair_invalid half_pair_valid far_end_full].each do |kind|
  ActiveRecord::Base.transaction(requires_new: true) do
    story = FactoryBot.create(:story)
    location = FactoryBot.create(:location, :stub, story: story, name: "Workshop", population: "nobody")
    case kind
    when "already_has_exit"
      way_back = FactoryBot.create(:location, story: story, name: "Way Back")
      pair(location, way_back)
      FactoryBot.create(:location, story: story, name: "Old Mill")
      proposals = [ BAD.merge("name" => "Old Mill") ]
    when "complete_existing_pair"
      way_back = FactoryBot.create(:location, story: story, name: "Back Lane")
      pair(location, way_back)
      proposals = [ BAD ]
    when "duplicate_new_alias"
      proposals = [ GOOD, BAD.merge("name" => "The Back Lane") ]
    when "natural_key_self"
      proposals = [ GOOD, BAD.merge("name" => "The Workshop") ]
    when "forced_invalid", "forced_valid"
      FactoryBot.create(:location, story: story, name: "Old Mill")
      proposals = [ (kind == "forced_invalid" ? BAD : GOOD).merge("name" => "Old Mill") ]
    when "half_pair_invalid", "half_pair_valid"
      lane = FactoryBot.create(:location, story: story, name: "Back Lane")
      FactoryBot.create(:location_connection, location: lane, connected_location: location)
      proposals = [ kind == "half_pair_invalid" ? BAD : GOOD ]
    when "far_end_full"
      full = FactoryBot.create(:location, :stub, story: story, name: "Crowded Door")
      Location::ExitsSchema::MAX_EXITS.times do |index|
        neighbour = FactoryBot.create(:location, story: story, name: "Far Existing #{index}")
        pair(full, neighbour)
      end
      proposals = [ GOOD, BAD.merge("name" => "Crowded Door") ]
    when "capacity_reached"
      (Location::ExitsSchema::MAX_EXITS - 1).times do |index|
        neighbour = FactoryBot.create(:location, story: story, name: "Existing #{index}")
        pair(location, neighbour)
      end
      proposals = [ GOOD, BAD.merge("name" => "Discarded Extra") ]
    end
    provider = FakeAgent.new(DETAIL, { "exits" => proposals })
    error = nil
    begin
      BaseAgent.stub(:new, provider) { Location::Generator.new(location).realize! }
    rescue StandardError => failure
      error = [ failure.class.name, failure.message ]
    end
    location.reload
    checkpoint = location.generation_checkpoint
    # Apply the exact writer loops without preflight to establish whether these
    # same attributes actually require an invalid edge. All rows roll back.
    writer = Location::Generator.new(location)
    writer_error = nil
    begin
      proposals.each { |attributes| writer.send(:connect_exit!, attributes) if writer.room_for_exits.positive? }
      proposals.each { |attributes| writer.send(:connect_exit!, attributes, into_written: true) } unless location.exits.exists?
    rescue StandardError => failure
      writer_error = [ failure.class.name, failure.message ]
    end
    puts({case: kind, realization_error: error, detail_level: location.detail_level,
          checkpoint_phase: checkpoint&.fetch("phase", nil), cached_exits: checkpoint&.key?("exits"),
          writer_error: writer_error, written_exits: location.exits.pluck(:name)}.to_json)
    raise ActiveRecord::Rollback
  end
end
