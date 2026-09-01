# Wires the `chats` / `messages` tables into the game.
#
# They existed and were wired with `acts_as_chat` before this, but every agent
# built a bare `RubyLLM::Chat`, so nothing was ever written to either. These
# columns are what makes a written row findable afterwards.
#
#   chats.purpose        which agent the conversation is with. A key into
#                        Chat::PURPOSES, not free text.
#   chats.playthrough    whose game it belongs to. Nullable, because
#                        world-building (`rake game:new`) has no playthrough.
#   chats.character      set on the ONE durable conversation kind -- talking to
#                        somebody. (playthrough, character, purpose) is its key,
#                        which is what lets a later turn pick the same chat up.
#   messages.scene       WHICH TURN a message was exchanged on. On the messages
#                        rather than on the chat, because a durable conversation
#                        spans many turns and a turn's cost has to come out
#                        exactly: `scene.messages.sum(:output_tokens)`.
#   messages.content_raw the structured answer. Without it RubyLLM stores a
#                        schema'd response as `content: nil` and drops the JSON,
#                        so every schema'd call in this app -- which is all but
#                        two -- would persist an empty assistant message.
class RecordConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :purpose, :string
    add_reference :chats, :playthrough, foreign_key: true
    add_reference :chats, :character, foreign_key: true
    add_index :chats, [ :playthrough_id, :character_id, :purpose ], name: "index_chats_on_conversation_key"

    add_reference :messages, :scene, foreign_key: true
    add_column :messages, :content_raw, :json
  end
end
