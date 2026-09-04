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
#
# AN ITEM IS MATCHED AGAINST ONE GAME'S OWN ROWS FIRST, and that is the one
# place the wider set would be wrong rather than merely wide. Since the
# captain's ruling of 2026-09-04 a world holds the template of a thing and one
# copy of it per playthrough that has seen it, all under one name, so a
# story-wide match would find four rows called "ward stamp" and drop every take
# in the database as ambiguous. A take belongs to one playthrough, the
# classifier's own chat says which (`chats.playthrough_id`), and what that turn
# moved was that playthrough's copy -- so its own rows are the set, and the
# world's own rows are the fallback for a turn whose chat has no playthrough on
# it. `Item.in_story` is the union both are drawn from, which is the query this
# used to keep a copy of without the carried leg: a `drop` of something a party
# was holding read as unrecoverable, because the row it named was in nobody's
# hands and no room.
class Scene::TransitionBackfill
  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Returns `{ labelled:, drifted:, unrecoverable: }`.
  def run(dry_run: false)
    counts = Hash.new(0)

    unlabelled.find_each do |scene|
      exchange = classifier_exchange(scene)
      answer = exchange&.answer
      action = answer && answer["intent"]

      if action.blank? || Playthrough::IntentSchema::INTENTS.exclude?(action)
        counts[:unrecoverable] += 1
        next
      end

      target = answer["target"].to_s
      resolved = target.blank? || target == Playthrough::IntentSchema::NOTHING ? nil : record_for(action, target, exchange&.playthrough)

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

  # THE CLASSIFIER'S OWN STRUCTURED REPLY, filed against this scene, AND WHOSE
  # GAME IT WAS. `content` is empty on a schema'd call and `content_raw` is the
  # parsed answer -- the same field `Eval` reads a historical run back out of.
  # The playthrough comes off the same chat row rather than out of a second
  # query, because it is only ever wanted alongside the answer.
  Exchange = Data.define(:answer, :playthrough)

  def classifier_exchange(scene)
    row = Message.joins(:chat)
                 .where(scene_id: scene.id, role: "assistant", chats: { purpose: "classifier" })
                 .order(:id)
                 .pick(:content_raw, "chats.playthrough_id")
    return nil if row.nil?

    raw, playthrough_id = row
    answer = raw.is_a?(String) ? JSON.parse(raw) : raw
    return nil if answer.nil?

    Exchange.new(answer: answer, playthrough: playthrough_id && Playthrough.find_by(id: playthrough_id))
  rescue JSON::ParserError
    nil
  end

  # The record the name meant, out of the set the action reads against, or nil
  # when this story no longer has one -- or has two that answer to it.
  def record_for(action, name, playthrough)
    found =
      case action
      when "move" then story.locations.select { |place| place.name.to_s.casecmp?(name) }
      when "talk" then story.characters.select { |who| who.fullname.to_s.casecmp?(name) || who.nickname.to_s.casecmp?(name) }
      when "take", "drop" then item_named(name, playthrough)
      else []
      end

    found.one? ? found.first : nil
  end

  # THIS GAME'S OWN ROW OF THAT NAME, or the world's own if the turn cannot be
  # attributed to a game. Two rows of one name in one layer is still refused --
  # `found.one?` above -- which is the rule this class follows everywhere.
  def item_named(name, playthrough)
    mine = playthrough ? items.select { |thing| thing.playthrough_id == playthrough.id && thing.name.to_s.casecmp?(name) } : []
    return mine if mine.any?

    items.select { |thing| thing.template? && thing.name.to_s.casecmp?(name) }
  end

  # EVERY ROW THIS STORY HAS, both layers and all three places -- `Item.in_story`,
  # the one place that query lives. It used to be a copy of it that predated the
  # scope and had no carried leg, so a `drop` of something a party was holding
  # named a row this could not see and was written off as unrecoverable.
  def items
    @items ||= Item.in_story(story).order(:id).to_a
  end
end
