# Synthetic browser states in the disposable worktree only. No model calls.
raise "not the evidence worktree" unless Rails.root.to_s.include?(".treehouse/")
raise "external database" unless File.realpath(ActiveRecord::Base.connection_db_config.database).start_with?(Rails.root.to_s + "/")
require "factory_bot"
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:lab_exits_vantage)
include FactoryBot::Syntax::Methods
Lab::Exits::Vantage.destroy_all
case ENV.fetch("AGREEMENT_STATE")
when "empty"
when "below"
  vantage = create(:lab_exits_vantage)
  create(:lab_exits_sample, :no_band_picked, vantage: vantage)
  create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
  vantage.judge!("Tide Flats", verdict: "good")
  vantage.judge!("Salt Chandlery", verdict: "bad", aspects: [ "teaser_wrong" ])
when "established"
  Story::Scoreboard::MIN_VERDICTS.times do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    vantage.judge!("Tide Flats", verdict: "good")
  end
  held = create(:lab_exits_vantage, world: Eval::HELD_OUT)
  create(:lab_exits_sample, :no_band_picked, vantage: held)
  held.judge!("Tide Flats", verdict: "good")
else
  raise "unknown evidence state"
end
