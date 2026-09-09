require "factory_bot_rails"
require "minitest/mock"
require Rails.root.join("test/support/fake_agent")
FactoryBot.find_definitions if FactoryBot.factories.count.zero?
ActiveRecord::Base.logger = nil
Rails.logger = Logger.new(File::NULL)
class SimulatedWorkerExit < Exception; end
DETAIL = { "description" => "A plain workshop with a closed bench.", "lore" => "Tools have been kept here for years.", "items" => [], "people" => [] }.freeze
GOOD = { "name" => "Back Lane", "teaser" => "A lane behind the workshop.", "distance" => "adjacent", "travel_method" => "walking" }.freeze

def assert!(condition, text)
  raise text unless condition
end

def no_provider
  BaseAgent.stub(:new, ->(*) { raise "Unexpected provider access during receipt replay" }) { yield }
end

%w[accepted_crash invalid_crash persistence_failure].each do |scenario|
  story = FactoryBot.create(:story)
  location = FactoryBot.create(:location, :stub, story: story, name: "Workshop", population: "nobody")
  generator = Location::Generator.new(location)
  exits = [ scenario == "invalid_crash" ? GOOD.merge("travel_method" => "teleporting") : GOOD ]
  provider = FakeAgent.new(DETAIL, { "exits" => exits })
  error = nil
  begin
    if scenario.end_with?("crash")
      generator.define_singleton_method(:connect_exit!) { |*| raise SimulatedWorkerExit, "after receipt, before graph writes" }
      BaseAgent.stub(:new, provider) { generator.realize! }
    else
      original_new = LocationConnection.method(:new)
      fail_save = lambda do |*args, **kwargs|
        edge = original_new.call(*args, **kwargs)
        edge.define_singleton_method(:save!) { |*| raise ActiveRecord::StatementInvalid, "simulated unavailable writer" }
        edge
      end
      LocationConnection.stub(:new, fail_save) { BaseAgent.stub(:new, provider) { generator.realize! } }
    end
  rescue SimulatedWorkerExit, ActiveRecord::StatementInvalid => caught
    error = caught.class.name
  end
  reloaded = Location.find(location.id)
  assert!(reloaded.generation_checkpoint.fetch("exits") == exits, "receipt lost: #{scenario}")
  assert!(reloaded.generation_checkpoint.fetch("phase") == "exits_pending", "detail lost")
  assert!(story.locations.count == 1 && reloaded.exits.empty?, "partial graph survived")
  if scenario == "invalid_crash"
    invalid_rejected = false
    begin
      no_provider { Location::Generator.new(reloaded).realize! }
    rescue Location::Generator::UnusableExitLabel
      invalid_rejected = true
    end
    assert!(invalid_rejected, "invalid provisional receipt not rejected")
    reloaded.reload
    assert!(!reloaded.generation_checkpoint.key?("exits"), "invalid receipt retained")
    assert!(reloaded.generation_checkpoint.key?("detail"), "paid detail removed")
    corrected = FakeAgent.new({ "exits" => [ GOOD ] })
    BaseAgent.stub(:new, corrected) { Location::Generator.new(Location.find(location.id)).realize! }
    assert!(corrected.schemas.map(&:name) == [ "Location::ExitsSchema" ], "retry paid for detail")
  else
    no_provider { Location::Generator.new(reloaded).realize! }
  end
  reloaded.reload
  assert!(reloaded.realized? && reloaded.generation_checkpoint.nil?, "retry did not finish")
  assert!(story.locations.count == 2 && reloaded.exits.count == 1, "retry duplicated graph")
  assert!(LocationConnection.where(location: story.locations).count == 2, "not exactly one bidirectional door")
  puts({scenario: scenario, initial_error: error, provisional_receipt_retained: true,
        invalid_receipt_discarded: scenario == "invalid_crash", fresh_instance_retry: "passed",
        exit_calls_on_retry: scenario == "invalid_crash" ? 1 : 0, provider_calls: 0}.to_json)
end
