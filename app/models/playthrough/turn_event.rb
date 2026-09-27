# ONE NUMBERED THING THAT HAPPENED DURING AN API TURN, kept so a client that
# drops its connection can pick the turn up where it left it.
#
# `NarrationJob`'s event adapter writes them as the turn runs; the events
# endpoint tails them as Server-Sent Events whose id is `sequence`, and a
# reconnect sends `Last-Event-ID` to be handed only the rows after it. They
# hang off the turn's own `Playthrough::Command`, so a turn's events are
# reached through the game that owns the turn and never by a bare id.
#
# `kind` is a closed list, the protocol's event names (docs/protocol/v1.md).
# `data` is the event's JSON body exactly as sent; the row is the record of
# what the client was told, and nothing reads it back as game state.
class Playthrough::TurnEvent < ApplicationRecord
  self.table_name = "playthrough_turn_events"

  KINDS = %w[started prose glance finished].freeze

  belongs_to :command, class_name: "Playthrough::Command", foreign_key: :playthrough_command_id,
                       inverse_of: :turn_events

  validates :kind, inclusion: { in: KINDS }
  validates :sequence, numericality: { only_integer: true, greater_than: 0 }

  scope :after, ->(sequence) { where("sequence > ?", sequence.to_i).order(:sequence) }

  # Appends the next event to a turn. Sequences are per turn and start at 1;
  # one job writes a turn's events, so the next number is the last plus one.
  def self.append!(command, kind, data)
    create!(command: command, kind: kind, data: data,
            sequence: where(playthrough_command_id: command.id).maximum(:sequence).to_i + 1)
  end

  def finished? = kind == "finished"
end
