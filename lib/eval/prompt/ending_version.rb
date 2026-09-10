# Ending identity separates record-derived framing from generated prelude data.
# Re-render the production builder with only the preceding Scene's description
# and summary replaced, through thread-local readers: no database write and no
# replacement of any request sent to a provider. Both fields matter because
# Moment reads the description directly and recap reads summary (or prose).
#
# Do not scrub strings out of an assembled prompt: prose may repeat record text,
# and its length may change which earlier recap lines fit. Rebuilding with fixed
# fields preserves those dependencies without pretending live prose is stable.
# The full live prompt and verbatim prelude survive beside the scaffold. Legacy
# prompt_digest/prompt_stable keep their original meanings. Ending request v2
# covers every ending case, plus corpus identity; other request versions stand.
module Eval::Prompt::EndingVersion
  extend self

  KEY = :eval_ending_request_capture
  FIELDS_KEY = :eval_ending_prelude_fields
  DESCRIPTION = "[generated prelude description]".freeze
  SUMMARY = "[generated prelude summary]".freeze

  module SceneFields
    def description
      fields = Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY]
      fields && id == fields[:id] ? Eval::Prompt::EndingVersion::DESCRIPTION : super
    end

    def summary
      fields = Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY]
      fields && id == fields[:id] ? Eval::Prompt::EndingVersion::SUMMARY : super
    end
  end

  module PromptCapture
    private

    def prompt_for(conclusion)
      live = super
      capture = Thread.current[Eval::Prompt::EndingVersion::KEY]
      return live unless capture

      prelude = conclusion.scene.previous_scene
      fields = { description: prelude.description, summary: prelude.summary }
      previous = Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY]
      begin
        Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY] = { id: prelude.id }
        scaffold = super
      ensure
        Thread.current[Eval::Prompt::EndingVersion::FIELDS_KEY] = previous
      end
      capture[:request] = {
        scaffold: Eval::RequestIdentity.request(agent.instructions, scaffold, agent.schema),
        prelude: fields, prelude_stable: false, prompt: live
      }
      live
    end
  end

  def capture
    Scene.prepend(SceneFields) unless Scene.ancestors.include?(SceneFields)
    Scene::Ending.prepend(PromptCapture) unless Scene::Ending.ancestors.include?(PromptCapture)
    previous = Thread.current[KEY]
    captured = {}
    Thread.current[KEY] = captured
    [ yield, captured[:request] ]
  ensure
    Thread.current[KEY] = previous
  end

  def current = Thread.current[KEY]&.fetch(:request, nil)

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
