# Cases name boundaries, not new prompt text. Upstream facts are the existing
# exported world; changing those facts changes the corpus identity as well.
class Eval::Genesis::Corpus
  Case = Data.define(:id, :producer, :seed, :why) do
    def to_h = { id: id, producer: producer, seed: seed, why: why }
  end
  PRODUCERS = %w[first_screen universe story character retry quest].freeze
  attr_reader :cases

  def self.load(path = Eval::Genesis::CORPUS)
    new(YAML.safe_load_file(path).map { |row| Case.new(**row.symbolize_keys) })
  end

  def initialize(cases)
    @cases = cases
    raise ArgumentError, "duplicate case id" unless cases.map(&:id).uniq.size == cases.size
    raise ArgumentError, "empty corpus" if cases.empty?
    cases.each do |kase|
      unless kase.id.present? && kase.why.present? && kase.seed.is_a?(Integer) && PRODUCERS.include?(kase.producer)
        raise ArgumentError, "invalid genesis case #{kase.inspect}"
      end
    end
  end

  def size = cases.size
end
