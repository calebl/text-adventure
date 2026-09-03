# WHAT AN OLD TURN DID, RECOVERED FROM THE ANSWER THAT DECIDED IT.
#
# `Scene#resolved_action` and `Scene#acted_on` are written by
# `Playthrough::Turn#play` from now on. Every turn played before them has
# neither, and a check that reads a transition simply cannot judge those turns
# -- which is honest, and also a waste, because the answer is still on disk:
# `Chat::KEEP_TURNS` has defaulted to nil since PR 97, so the classifier's own
# structured reply is stored against the very scene it produced
# (`BaseAgent#attribute_to!`). `rake game:backfill_transitions` runs this.
#
# THREE OUTCOMES, TOLD APART, and the third is the reason this is careful:
#
#   labelled       the answer named something the records still have. Both
#                  columns written.
#   drifted        the answer was `nothing` -- the player reached for a way out
#                  or a person the closed set did not have. The ACTION is
#                  written and the record is left nil, which is what that turn
#                  really was. `Playthrough::Drift` already counts it.
#   unrecoverable  there is no stored answer, or it named something these
#                  records no longer have. NOTHING is written.
#
# The third case is why the action is never written on its own out of a named
# target. An action with no record reads as drift to `Scene#took?` and to
# `Story::Audit`, so labelling a resolved take that way would manufacture a
# drift the game never had. A blank column says "not known"; a wrong one says
# something false.
#
# NAMES ARE MATCHED AGAINST THE STORY, not against the room's exits and cast as
# they stood on that turn -- those are not recoverable, the world moves
# (`WorldMechanic::ShuffleConnections`) and the cast a scene records is only
# written on some branches. So the set is wider than the classifier's was and a
# name two records answer to is dropped rather than guessed at, on the same
# rule `Story::Audit#place_names` follows.
class Scene::TransitionBackfill
  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns `{ labelled:, drifted:, unrecoverable: }`.
  def run(dry_run: false)
    counts = Hash.new(0)

    unlabelled.find_each do |scene|
      answer = classifier_answer(scene)
      action = answer && answer["intent"]

      if action.blank? || Playthrough::IntentSchema::INTENTS.exclude?(action)
        counts[:unrecoverable] += 1
        next
      end

      target = answer["target"].to_s
      resolved = target.blank? || target == Playthrough::IntentSchema::NOTHING ? nil : record_for(action, target)

      if resolved.nil? && target.present? && target != Playthrough::IntentSchema::NOTHING
        counts[:unrecoverable] += 1
        next
      end

      counts[resolved ? :labelled : :drifted] += 1
      scene.update_columns(resolved_action: action, acted_on_type: resolved&.class&.name, acted_on_id: resolved&.id) unless dry_run
    end

    counts
  end

  private

  # Turns with no action on record, and never the opening arrival: that scene
  # is world data written before anybody played, so it did nothing and has no
  # classifier exchange to read.
  def unlabelled
    story.scenes.where(resolved_action: nil, is_opening: false)
  end

  # THE CLASSIFIER'S OWN STRUCTURED REPLY, filed against this scene. `content`
  # is empty on a schema'd call and `content_raw` is the parsed answer -- the
  # same field `Eval` reads a historical run back out of.
  def classifier_answer(scene)
    raw = Message.joins(:chat)
                 .where(scene_id: scene.id, role: "assistant", chats: { purpose: "classifier" })
                 .order(:id)
                 .pick(:content_raw)

    raw.is_a?(String) ? JSON.parse(raw) : raw
  rescue JSON::ParserError
    nil
  end

  # The record the name meant, out of the set the action reads against, or nil
  # when this story no longer has one -- or has two that answer to it.
  def record_for(action, name)
    found =
      case action
      when "move" then story.locations.select { |place| place.name.to_s.casecmp?(name) }
      when "talk" then story.characters.select { |who| who.fullname.to_s.casecmp?(name) || who.nickname.to_s.casecmp?(name) }
      when "take", "drop" then items.select { |thing| thing.name.to_s.casecmp?(name) }
      else []
      end

    found.one? ? found.first : nil
  end

  # Everything this story has a row for, in somebody's hands or lying in one of
  # its rooms -- the union of the two sets `take` and `drop` resolve against.
  def items
    @items ||= Item.where(character: story.characters).or(Item.where(location: story.locations)).order(:id).to_a
  end
end
