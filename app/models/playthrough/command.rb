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

  # WHETHER THE GAME HAS ALREADY MOVED PAST THIS SUBMISSION, and the reason a
  # redelivery is not always harmless.
  #
  # A duplicate delivery touches no records -- `#execute!` hands back what this
  # submission produced and runs nothing -- but its consumer then paints that
  # stored outcome as the page. The accepted-order drain makes a LATER
  # submission finish first as an ordinary matter, so the overtaken job's own
  # delivery arrives after the newer turn has landed: a refusal box for a line
  # typed in the room before this one, over the room the player is standing in
  # now, taking whatever they have typed since with it. An obsolete failure
  # notice replaces newer successful state the same way.
  #
  # So a submission with a newer sibling the game has started or finished says
  # nothing at all. The NEWEST submission is never overtaken, which is what
  # keeps a legitimate redelivery of the current line -- its refusal, its
  # crisis notice -- refreshing the page accurately.
  def overtaken?
    return false if status == "pending"

    playthrough.commands.where("id > ?", id).where.not(status: "pending").exists?
  end

  # WHAT THIS SUBMISSION PRODUCED, rebuilt from its own columns: the Scene it
  # wrote, the refusal the engine answered with, or nil for one that failed.
  # `#execute!` reads it for a duplicate delivery and `Playthrough::Turn#play`
  # reads it for an overtaken one, which is answered and never broadcast.
  def outcome
    if refusal.blank?
      scene = result_scene
      scene.safety_notice = true if scene && error_kind == "crisis"
      return scene
    end

    Playthrough::Refusal.new(**refusal.symbolize_keys.merge(kind: refusal.fetch("kind").to_sym))
  end

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
end
