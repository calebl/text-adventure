# Offline only: test_helper clears model credentials; network responses below
# are fixtures. These class definitions exist only inside this test process.
workspace = File.expand_path("../../..", __dir__)
candidate = File.join(__dir__, "npc-candidate")
require File.join(workspace, "test/test_helper")
load File.join(__dir__, "npc-test-arrival-generator.rb")
Interaction.send(:remove_const, :Schema) if Interaction.const_defined?(:Schema, false)
load File.join(candidate, "app/models/interaction/schema.rb")
load File.join(candidate, "app/agents/InteractionAgent.rb")
load File.join(candidate, "app/models/interaction.rb")
load File.join(candidate, "app/models/playthrough/turn.rb")
%w[
  test/agents/interaction_agent_agency_test.rb
  test/agents/interaction_agent_test.rb
  test/models/chat_persistence_test.rb
  test/models/playthrough/turn_conversations_test.rb
  test/models/playthrough/turn_test.rb
].each { |path| require File.join(candidate, path) }
%w[
  test/models/playthrough/adversarial_flow_test.rb
  test/models/playthrough/npc_action_test.rb
  test/models/playthrough/npc_state_test.rb
  test/lib/engine_sweep_test.rb
].each { |path| require File.join(workspace, path) }
