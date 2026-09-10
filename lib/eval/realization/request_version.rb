# Normalize random inputs BEFORE rendering, never whole instruction lines.
# Exercise every engine-supported count so singular/plural/nobody wording and
# the dynamically emitted required lists and bounds all remain detectable.
# Slot data is fixed at the registry seam; the generator still writes every
# literal word. The exits identity omits generated assistant detail history.
module Eval::Realization::RequestVersion
  extend self

  def offline(corpus = Eval::Realization.corpus)
    requests = {}
    EngineSweep.without_a_model do
      Eval::Realization::Version.designated_cases(corpus).each do |shape, kase|
        Eval::Realization::Stage.open([ kase ]) do |stages|
          generator = stages.fetch(kase.id).generator
          counts = generator.location.place? ? [ 0 ] : (0..Location::Population::MOST).to_a
          requests[shape] = counts.map { |count| built(generator, count) }
        end
      end
    end
    Eval::RequestIdentity.of(requests)
  end

  def built(generator, count)
    registry = generator.cast_registry
    registry.define_singleton_method(:allowance) { count }
    registry.define_singleton_method(:slots) do
      Array.new(count) { { race: nil, age: 30, sex: "woman" } }
    end
    requests = [ Eval::RequestIdentity.request(generator.system_prompt, generator.detail_prompt, generator.detail_schema) ]
    unless generator.interior_room? || generator.location.place?
      requests << Eval::RequestIdentity.request(generator.system_prompt, generator.exits_prompt, Location::ExitsSchema)
    end
    requests
  end
end
