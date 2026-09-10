# Keep the readings, not only the figures: rejected answers and their emitted
# schemas are needed for honest offline rescoring. Receipts use the registry's
# prices at purchase time; cached input is conservatively charged at full price.
class Eval::Genesis::Result
  attr_reader :document
  def initialize(document) = @document = document
  def self.load(directory) = new(JSON.parse(File.read(Pathname.new(directory).join(Eval::Genesis::RESULTS))))
  def passes = document.fetch("passes")
  def rows = passes.flat_map { |pass| pass.fetch("readings") }
  def arms = document.fetch("arms")
  def corpus_digest = document.fetch("corpus_digest")
  def request_digests = document.fetch("request_digests")
  def reps = document.fetch("reps")
  def cost = rows.sum { |row| row["cost_usd"].to_f }
  def receipt_missing = rows.count { |row| row["receipt_missing"] }

  def values(code, call: nil)
    passes.map do |pass|
      rows = pass.fetch("readings")
      rows = rows.select { |row| row["call"] == call } if call
      return_value(code, rows)
    end
  end

  def return_value(code, rows)
    return rows.count { |row| row["error"] || row["receipt_missing"] } if code.to_s == "failures"

    Eval::Genesis::Scorer.new(rows).rate(code)
  end

  def write!(directory)
    directory = Pathname.new(directory)
    FileUtils.mkdir_p(directory)
    document["cost_usd"] = cost
    document["receipt_missing"] = receipt_missing
    document["request_stable"] = rows.all? do |row|
      row["request_digest"] == request_digests.dig(row["id"], row["call"])
    end
    File.write(directory.join(Eval::Genesis::RESULTS), JSON.pretty_generate(document) + "\n")
  end
end
