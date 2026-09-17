# Executable offline proof at the same wrapper used before live reservations.
# A fake downstream method records whether dispatch reached the spending seam.
require "json"
require ENV.fetch("EVAL_BUDGET_HELPER")
require_relative "payload_gate"

requests = JSON.parse(File.read(File.join(__dir__, "requests.json"))).fetch("requests")
request = requests.values.first
case_id = requests.keys.first
messages = Class.new(Array) { def order(*) = self }.new
schema = Class.new do
  define_method(:to_json_schema) { request.fetch("schema") }
end
boundary = Class.new do
  attr_reader :instructions, :schema, :chat, :calls
  define_method(:initialize) do
    @instructions = request.fetch("system")
    @schema = schema
    @chat = Struct.new(:messages).new(messages)
    @calls = 0
  end
  def ask(*)
    @calls += 1
    :reached_fake_boundary
  end
end
boundary.prepend(PhysicalRealizationPayload::BeforeBudget)
passed = []
%w[matching changed_prompt changed_schema changed_history repeated missing_context].each do |probe|
  gate = PhysicalRealizationPayload::Gate.new(requests: requests, allowed: [ [ case_id, 1 ] ])
  gate.current = [ case_id, 1 ] unless probe == "missing_context"
  PhysicalRealizationPayload.gate = gate
  agent = boundary.new
  prompt = request.fetch("user")
  prompt += "\nUnapproved change" if probe == "changed_prompt"
  if probe == "changed_schema"
    altered = request.fetch("schema").deep_dup
    altered["name"] = "unapproved"
    agent.instance_variable_set(:@schema, Class.new { define_method(:to_json_schema) { altered } })
  end
  if probe == "changed_history"
    message = Struct.new(:role, :to_llm).new("user", Struct.new(:content).new("unapproved history"))
    changed = messages.class.new([ message ])
    agent.instance_variable_set(:@chat, Struct.new(:messages).new(changed))
  end
  agent.ask(prompt) if probe == "repeated"
  if probe == "matching"
    raise "Positive request did not reach the boundary" unless agent.ask(prompt) == :reached_fake_boundary && agent.calls == 1
  else
    begin
      agent.ask(prompt)
      raise "Unapproved request reached the boundary: #{probe}"
    rescue PhysicalRealizationPayload::Refused
      expected_calls = probe == "repeated" ? 1 : 0
      raise "Gate acted after the boundary" unless agent.calls == expected_calls
    end
  end
  passed << probe
end
PhysicalRealizationPayload.gate = nil
puts JSON.pretty_generate({ offline: true, provider_calls: 0, ledger_writes: 0, passed: passed })
