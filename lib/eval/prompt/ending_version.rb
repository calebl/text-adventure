# Ending identity separates record-derived framing from generated prelude data.
# Re-render the engine's ending request with only the preceding Scene's
# description and summary replaced, in the rows handed to the builder: no
# database write and no replacement of any request sent to a provider. Both
# fields matter because the moment reads the description directly and the
# recap reads summary (or prose).
#
# Do not scrub strings out of an assembled prompt: prose may repeat record text,
# and its length may change which earlier recap lines fit. Rebuilding with fixed
# fields preserves those dependencies without pretending live prose is stable.
# The full live prompt and verbatim prelude survive beside the scaffold. Legacy
# prompt_digest/prompt_stable keep their original meanings. Ending request v2
# covers every ending case, plus corpus identity; other request versions stand.
module Eval::Prompt::EndingVersion
  extend self

  DESCRIPTION = "[generated prelude description]".freeze
  SUMMARY = "[generated prelude summary]".freeze

  # THE SCAFFOLD OF ONE ENDING: the engine's request for `playthrough`'s last
  # paragraph, for the reached `outcome`, built from the rows the connection
  # sees with the `prelude` scene's description and summary replaced by the
  # fixed words above; beside it the prelude as it was and the live prompt the
  # engine sent (`prompt`).
  def scaffold(playthrough, outcome:, prelude:, prompt:)
    rows = Playthrough::Requests.dump
    rows.fetch("scenes").each do |row|
      next unless row["id"] == prelude.id

      row["description"] = DESCRIPTION
      row["summary"] = SUMMARY
    end
    built = Playthrough::Requests.build(:ending, rows: JSON.generate(rows), playthrough: playthrough.id, outcome: outcome.id)
    {
      scaffold: Eval::RequestIdentity.request(built.fetch("system"), built.fetch("user"), nil),
      prelude: { description: prelude.description, summary: prelude.summary }, prelude_stable: false,
      prompt: prompt
    }
  end

  def identity(requests, corpus)
    Eval::RequestIdentity.of(corpus: Eval::Prompt.digest(corpus), requests: requests)
                         .merge("version" => 2, "scope" => "ending_scaffold", "prelude_stable" => false)
  end

  def of(passes, corpus)
    readings = passes.flat_map(&:readings).select(&:ending_request)
    grouped = readings.group_by(&:id).sort.to_h
    scaffolds = grouped.transform_values { |rows| rows.first.ending_request[:scaffold] }
    {
      request_identity: identity(scaffolds, corpus),
      ending_requests: {
        version: 2,
        scaffold_stable: grouped.values.all? { |rows| rows.map { |row| row.ending_request[:scaffold] }.uniq.one? },
        complete: grouped.keys == corpus.cases.map(&:id).sort,
        readings: readings.map { |row| { id: row.id, arm: row.arm, rep: row.rep, **row.ending_request } }
      }
    }
  end
end
