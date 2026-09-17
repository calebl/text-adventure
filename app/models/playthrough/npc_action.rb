# The immediate effects a character may choose during a conversation. A choice
# is an opaque token in a table built from this game's records, not an action
# extracted from dialogue. The table is rebuilt when the answer arrives, so a
# stale choice, somebody else's item or a dead/absent speaker cannot act.
#
# Speech and private resolutions remain prose. Only this class writes the
# supported effects, before the narrator sees them; its receipt says exactly
# which choice was applied or rejected and is kept on the Interaction.
class Playthrough::NpcAction
  NONE = "none".freeze
  Result = Data.define(:action, :status, :fact) do
    def attributes = { engine_action: action, action_status: status, action_fact: fact }
    def applied? = status == "applied"
  end

  attr_reader :playthrough, :character, :offered_item

  def initialize(playthrough, character, offered_item: nil)
    @playthrough = playthrough
    @character = character
    @offered_item = offered_item
  end

  def choices
    available = { NONE => "Speak without transferring anything or changing an agreement." }
    return available unless present?

    if offered_item && playthrough.carried.exists?(id: offered_item.id)
      available["accept:#{offered_item.id}"] = "Accept the offered #{offered_item.name} from #{playthrough.character.fullname}; it becomes yours."
    end
    playthrough.items_held_by(character).each do |item|
      available["give:#{item.id}"] = "Give #{item.name} to #{playthrough.character.fullname}." if playthrough.character
    end
    if playthrough.foes_in(playthrough.current_location).include?(character)
      available["ceasefire"] = "Stop fighting #{playthrough.character&.fullname || 'the player'}; another attack can break the truce."
    elsif following?
      available["stop_following"] = "Stay in #{playthrough.current_location.name} when the player leaves."
    else
      available["follow"] = "Accompany #{playthrough.character&.fullname || 'the player'} when they leave this room."
    end
    available
  end

  def apply!(choice)
    choice = choice.to_s
    return receipt(NONE, "none", "#{character.fullname} changes no possessions, travel agreement or ceasefire.") if choice == NONE

    Playthrough::NpcState.transaction do
      unless choices.key?(choice)
        return receipt(choice, "rejected", "The proposed action was rejected: it is unavailable. No possessions, travel agreement or ceasefire changed.")
      end

      fact = case choice
      when /\Aaccept:(\d+)\z/
        item = playthrough.carried.find(Regexp.last_match(1))
        item.update!(character: character, location: nil, **Location::Placement.unplaced)
        "#{character.fullname} accepted #{item.name}; the player no longer carries it and #{character.fullname} now holds it."
      when /\Agive:(\d+)\z/
        item = playthrough.items_held_by(character).find(Regexp.last_match(1))
        item.update!(character: nil, location: nil, **Location::Placement.unplaced)
        "#{character.fullname} gave #{item.name} to #{playthrough.character.fullname}; the player now carries it."
      when "follow"
        state!.update!(following: true, location: playthrough.current_location)
        "#{character.fullname} is now accompanying #{playthrough.character&.fullname || 'the player'} and will travel with them."
      when "stop_following"
        state!.update!(following: false, location: playthrough.current_location)
        "#{character.fullname} stopped accompanying the player and remains in #{playthrough.current_location.name}."
      when "ceasefire"
        state!.make_peace!
        "#{character.fullname} stopped fighting the player. The ceasefire holds unless the player attacks again."
      end
      receipt(choice, "applied", fact)
    end
  end

  private

  def present?
    playthrough && !playthrough.over? && character != playthrough.character &&
      character.story_id == playthrough.story_id && playthrough.cast_in(playthrough.current_location).include?(character)
  end

  def state = playthrough.npc_states.find_by(character: character)

  def following?
    row = state
    row ? row.following? : character.is_companion?
  end

  def state!
    playthrough.npc_states.find_or_create_by!(character: character) do |row|
      row.location = playthrough.location_of(character) || playthrough.current_location
    end
  end

  def receipt(action, status, fact) = Result.new(action: action, status: status, fact: fact)
end
