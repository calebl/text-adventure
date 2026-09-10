# Unavailable is not zero. Every rate prints its own denominator, beside the
# failures and spend that prevent a bench full of rejected calls looking clean.
class Eval::Genesis::Board
  def initialize(result) = @result = result
  def lines
    scorer = Eval::Genesis::Scorer.new(@result.rows)
    [ "Genesis: #{@result.arms.join(', ')} — record fidelity only",
      "Cost at recorded registry prices: $#{format('%.6f', @result.cost)}; missing receipts: #{@result.receipt_missing}",
      "Failures per pass: #{@result.values(:failures).inspect}",
      "| Check | Flagged / judgeable | Per-pass range |", "| --- | --- | --- |" ] +
      Eval::Genesis::Scorer::CHECKS.keys.map do |code|
        count = scorer.judgeable_for(code)
        values = @result.values(code).compact
        range = values.empty? ? "unavailable" : "#{values.min.round(4)}–#{values.max.round(4)}"
        "| #{code} | #{count.zero? ? 'unavailable' : "#{scorer.flagged_for(code).size} / #{count}"} | #{range} |"
      end + [ "Believability, prose identity fidelity, opener coherence and quest quality: unavailable; human lab required." ]
  end
end
