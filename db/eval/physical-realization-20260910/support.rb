# Offline provenance helpers. Request assembly needs a real, unasked BaseAgent
# to expose its stored history. Block Chat#ask rather than its construction.
module PhysicalRealizationEvidence
  class ModelCall < Exception; end

  def self.offline
    original = Chat.instance_method(:ask)
    Chat.define_method(:ask) { |*| raise ModelCall, "Offline evidence attempted a provider call" }
    yield
  ensure
    Chat.define_method(:ask, original) if original
  end
end
