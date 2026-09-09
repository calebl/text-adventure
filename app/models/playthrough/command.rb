# One submitted browser command, independent of how often its job is delivered.
#
# A SUBMISSION IS ITS TOKEN AND ITS TEXT, and it takes both halves to tell the
# three cases apart. One RESEND of one submit -- a double-click, a browser
# retrying a POST whose response was lost, a job delivered twice -- carries the
# same token and the same line, and is one turn. Two DIFFERENT lines can share
# a token, because the battle panel puts every one of its buttons on the page at
# once, and they are two turns. What neither half answers on its own is a second
# submit of the SAME line, which is why the token is spent on use:
# `TurnsController#create` hands the browser a fresh one with every accepted
# submission, so a repeated "attack the guard" arrives under a new token and
# takes its own turn. Keying on the token alone refused the new line and lost
# it; keying on token-and-text alone merged the repeat.
#
# `id` IS THE ACCEPTED ORDER, and the only record of it. Two submissions can be
# accepted while a turn is running and their jobs can reach the lock in either
# order, so `Playthrough::Turn#play` plays every pending row up to its own in
# `id` order rather than whichever job won the race.
#
# Execute only under GameLock's playthrough claim. Completed deliveries reuse
# their outcome without touching the engine or making a model call. A worker
# that disappears while running leaves a visible interrupted command; replaying
# it could repeat a half-finished effect, so it is never silently replayed.
# Provider failures after a committed action instead finish with factual prose
# (Scene::Narrator and Scene::Generator), including the world's response.
class Playthrough::Command < ApplicationRecord
  self.table_name = "playthrough_commands"

  class InterruptedError < StandardError; end
  class PreviouslyFailedError < StandardError; end

  STATUSES = %w[pending running completed failed].freeze

  belongs_to :playthrough
  belongs_to :result_scene, class_name: "Scene", optional: true

  validates :request_token, presence: true, length: { maximum: 128 }
  validates :command, presence: true
  validates :status, inclusion: { in: STATUSES }

  def self.accept!(playthrough, command, request_token)
    create_or_find_by!(playthrough: playthrough, request_token: request_token, command: command)
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
