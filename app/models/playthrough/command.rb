# One submitted browser command, independent of how often its job is delivered.
# Its token belongs to the form, not to the text: two intentional "wait" turns
# are different submissions, while two deliveries of one form are one turn.
#
# Execute only under GameLock's playthrough claim. Completed deliveries reuse
# their outcome without touching the engine or making a model call. A worker
# that disappears while running leaves a visible interrupted command; replaying
# it could repeat a half-finished effect, so it is never silently replayed.
# Provider failures after a committed action instead finish with factual prose
# (Scene::Narrator and Scene::Generator), including the world's response.
class Playthrough::Command < ApplicationRecord
  self.table_name = "playthrough_commands"

  class TokenConflict < StandardError; end
  class InterruptedError < StandardError; end
  class PreviouslyFailedError < StandardError; end

  STATUSES = %w[pending running completed failed].freeze

  belongs_to :playthrough
  belongs_to :result_scene, class_name: "Scene", optional: true

  validates :request_token, presence: true, length: { maximum: 128 }
  validates :command, presence: true
  validates :status, inclusion: { in: STATUSES }

  def self.accept!(playthrough, command, request_token)
    submission = create_or_find_by!(playthrough: playthrough, request_token: request_token) do |row|
      row.command = command
    end
    raise TokenConflict, "A submission token cannot name two commands" unless submission.command == command

    submission
  end

  def completed? = status == "completed"

  def execute!
    return outcome if completed?
    raise InterruptedError, "A previous worker stopped during this turn" if status == "running"
    if status == "failed"
      raise BaseAgent::CrisisResponseError if error_kind == "crisis"

      raise PreviouslyFailedError, "This submission has already failed"
    end

    update!(status: "running")
    begin
      result = yield
      attributes = { status: "completed" }
      attributes[:result_scene] = result if result.is_a?(Scene)
      attributes[:error_kind] = "crisis" if result.is_a?(Scene) && result.safety_notice
      if result.is_a?(Playthrough::Refusal)
        attributes[:refusal] = { kind: result.kind, typed: result.typed, fact: result.fact, offer: result.offer }
      end
      update!(attributes)
      result
    rescue StandardError => e
      update!(status: "failed", error_kind: e.is_a?(BaseAgent::CrisisResponseError) ? "crisis" : "error")
      raise
    end
  end

  private

  def outcome
    if refusal.blank?
      scene = result_scene
      scene.safety_notice = true if scene && error_kind == "crisis"
      return scene
    end

    Playthrough::Refusal.new(**refusal.symbolize_keys.merge(kind: refusal.fetch("kind").to_sym))
  end
end
