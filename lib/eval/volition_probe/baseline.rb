# WHAT A KEPT VOLITION BASELINE SET SHOWS, RECOMPUTED FROM ITS FILES ALONE.
#
# Free: it reads `receipts.json` and the `requests.json` the set was measured
# on, and nothing else. Per room it gives each person's act on every
# repetition (as the sentence that act was offered under), how often the
# repetitions agreed, which of the four objects of desire the answer said the
# act served, and the pressure scores; across the set, how often pressure
# crossed `Playthrough::Volition::SystemOne::PRESSURE_THRESHOLD` -- the
# answers where the typed act replaces the die -- and the cost.
#
# A SHAPE IS READ OFF THE OFFERED SENTENCE, because the request carries labels
# and sentences and never a token (`Playthrough::Volition::State`). The
# sentences are `Playthrough::Volition#choices`' own, so each opening names
# one shape.
module Eval
  module VolitionProbe
    module Baseline
      SHAPES = [
        [ /\AStay where you are/, "wait" ], [ /\AStay in .* when the player leaves/, "stop_following" ],
        [ /\AWalk out of/, "move" ], [ /\APick up/, "take" ], [ /\AGive/, "give" ], [ /\AAccompany/, "follow" ]
      ].freeze

      module_function

      def shape_of(sentence) = SHAPES.find { |pattern, _| pattern.match?(sentence.to_s) }&.last || "unknown"

      def summary(set)
        dir = VolitionProbe::ROOT.join(set)
        kept = JSON.parse(dir.join("receipts.json").read)
        requests = JSON.parse(dir.join("requests.json").read).index_by { |room| room["room"] }
        answered = kept["receipts"].select { |r| r["status"] == 200 }
        threshold = Playthrough::Volition::SystemOne::PRESSURE_THRESHOLD

        people = answered.group_by { |r| r["room"] }.flat_map do |room, receipts|
          request = requests.fetch(room)
          request["state"]["characters"].map { |key, person| person_summary(request, key, person, receipts, threshold).merge("room" => room) }
        end

        answers = people.flat_map { |p| p["reps"] }
        pressures = answers.map { |a| a["pressure"].to_f }
        costs = answered.map { |r| r["cost"].to_f }
        {
          "set" => set, "model" => kept["model"], "calls" => kept["receipts"].size, "succeeded" => answered.size,
          "failed" => kept["receipts"].reject { |r| r["status"] == 200 }.map { |r| r.slice("call", "room", "status", "error_body") },
          "people" => people,
          "shapes_chosen" => answers.map { |a| a["shape"] }.tally.sort.to_h,
          "serves" => answers.map { |a| a["serves"] }.tally.sort.to_h,
          "serves_by_shape" => answers.group_by { |a| a["shape"] }.sort.to_h.transform_values { |g| g.map { |a| a["serves"] }.tally.sort.to_h },
          "mean_agreement" => mean(people.map { |p| p["agreement"].to_f }),
          "pressure_mean" => mean(pressures), "pressure_min" => pressures.min, "pressure_max" => pressures.max,
          "pressure_crossed" => pressures.count { |p| p >= threshold }, "answers" => answers.size, "threshold" => threshold,
          "receipt_total" => costs.sum, "per_call" => costs.empty? ? nil : costs.sum / costs.size,
          "credit_delta" => kept.dig("credits_after", "total_usage").to_f - kept.dig("credits_before", "total_usage").to_f
        }
      end

      def person_summary(request, key, person, receipts, threshold)
        criteria = request["questions"]["#{key}:act"]["criteria"]
        reps = receipts.sort_by { |r| r["rep"] }.map do |r|
          act = r.dig("answers", "#{key}:act", "choice")
          { "rep" => r["rep"], "act" => act, "sentence" => criteria[act], "shape" => shape_of(criteria[act]),
            "serves" => r.dig("answers", "#{key}:serves", "choice"),
            "pressure" => r.dig("answers", "#{key}:pressure", "noul") }
        end
        pressures = reps.map { |rep| rep["pressure"].to_f }
        modal = reps.map { |rep| rep["act"] }.tally.max_by { |_, count| count }
        { "person" => key, "name" => person["name"], "pursuits" => "#{person["desire_pursuit"]}/#{person["need_pursuit"]}",
          "offered" => criteria.size, "reps" => reps, "modal_act" => modal&.first, "modal_sentence" => criteria[modal&.first],
          "agreement" => modal && modal.last.fdiv(reps.size),
          "pressure_mean" => mean(pressures), "pressure_min" => pressures.min, "pressure_max" => pressures.max,
          "pressure_sd" => sd(pressures), "crossed" => pressures.count { |p| p >= threshold } }
      end

      # The same summary as lines a person reads.
      def report(set)
        s = summary(set)
        lines = [ "#{s["set"]}: #{s["succeeded"]}/#{s["calls"]} calls answered (#{s["model"]})" ]
        s["failed"].each { |f| lines << "  FAILED call #{f["call"]} #{f["room"]}: #{f["status"]} #{f["error_body"]}" }
        s["people"].each do |p|
          lines << "#{p["room"]} #{p["person"]} #{p["name"]} (#{p["pursuits"]}, #{p["offered"]} acts offered)"
          lines << "  acts:     #{p["reps"].map { |r| r["act"] }.join(" ")}  agreement #{pct(p["agreement"])} -> #{p["modal_sentence"]}"
          lines << "  serves:   #{p["reps"].map { |r| r["serves"] }.join(" ")}"
          lines << format("  pressure: %s  mean %.3f sd %.3f, crossed %d/%d",
                          p["reps"].map { |r| r["pressure"] }.join(" "), p["pressure_mean"], p["pressure_sd"], p["crossed"], p["reps"].size)
        end
        lines << "shapes chosen: #{s["shapes_chosen"]}"
        lines << "serves: #{s["serves"]}"
        s["serves_by_shape"].each { |shape, tally| lines << "  #{shape}: #{tally}" }
        lines << "mean repetition agreement on the act: #{pct(s["mean_agreement"])}"
        lines << format("pressure: mean %.3f, range %s..%s; at or over %s in %d of %d answers",
                        s["pressure_mean"].to_f, s["pressure_min"], s["pressure_max"], s["threshold"], s["pressure_crossed"], s["answers"])
        lines << format("cost: %.9f USD over %d calls, %.9f per call; credit delta %.9f (shared account)",
                        s["receipt_total"], s["succeeded"], s["per_call"].to_f, s["credit_delta"])
        lines.join("\n")
      end

      def mean(values) = values.empty? ? nil : values.sum / values.size

      def sd(values)
        return nil if values.empty?

        m = mean(values)
        Math.sqrt(values.sum { |v| (v - m)**2 } / values.size)
      end

      def pct(value) = value ? "#{(value * 100).round}%" : "-"
    end
  end
end
