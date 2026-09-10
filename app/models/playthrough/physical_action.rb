# Physical attempts are choices assembled from this game's actual things and
# doorways. A model may select one token, never supply an effect or an amount.
# Rebuild the table before writing: a saved choice is not proof that a tool is
# still carried or a doorway still reachable. Turn journals the write and its
# receipt together, then gives the receipt to the narrator.
#
# Profiles and barriers are world parameters. Spent items and opened passages
# belong to one playthrough. A spent copy remains as a tombstone so visiting
# its template again cannot manufacture another dose or another sheet of paper.
class Playthrough::PhysicalAction
  Choice = Data.define(:kind, :item, :recipient, :connection, :tool) do
    def initialize(item: nil, recipient: nil, connection: nil, tool: nil, **rest) = super
    def token = ([ "use", kind ] + [ item, recipient, connection, tool ].map { |row| row&.id || 0 }).join(":")
    def subject = item || connection&.connected_location
    def records = [ item, recipient, connection&.connected_location, tool ].compact

    def argument
      return "#{item.name} to #{recipient.fullname}" if kind == "offer"
      target = subject.name
      tool ? "#{target} with #{tool.name}" : target
    end

    def name
      case kind
      when "consume" then "Consume #{item.name}"
      when "offer" then "Offer #{item.name} to #{recipient.fullname}; they may refuse"
      when "burn" then "Burn #{item.name} with #{tool.name}"
      when "unlock" then "Unlock the way to #{connection.connected_location.name} with #{tool.name}"
      when "pick" then "Pick the lock to #{connection.connected_location.name} with #{tool.name}"
      when "pry" then "Pry open the way to #{connection.connected_location.name} with #{tool.name}"
      when "force" then "Force open the jammed way to #{connection.connected_location.name}"
      end
    end
  end
  Result = Data.define(:status, :fact)

  attr_reader :playthrough
  def initialize(playthrough) = @playthrough = playthrough

  def choices
    return [] unless playthrough.character && playthrough.current_location && !playthrough.over?

    carried = playthrough.carried.order(:id).to_a
    cast = playthrough.cast_in(playthrough.current_location) - [ playthrough.character ]
    result = carried.select(&:consumable?).map { |item| Choice.new(kind: "consume", item: item) }
    carried.each do |item|
      cast.each { |person| result << Choice.new(kind: "offer", item: item, recipient: person) }
    end
    carried.select { |item| item.use_kind == "firestarter" }.each do |tool|
      (carried + playthrough.items_lying_in(playthrough.current_location).to_a).select(&:combustible?).each do |item|
        result << Choice.new(kind: "burn", item: item, tool: tool) unless item == tool
      end
    end
    LocationConnection.where(location: playthrough.current_location).order(:id).each do |edge|
      next if edge.open_for?(playthrough)

      case edge.barrier
      when "keyed"
        carried.each do |tool|
          kind = if tool.use_kind == "key" && tool.template_id == edge.key_template_id
            "unlock"
          elsif tool.use_kind == "lockpick"
            "pick"
          end
          result << Choice.new(kind: kind, connection: edge, tool: tool) if kind
        end
      when "jammed"
        result << Choice.new(kind: "force", connection: edge)
        carried.select { |item| item.use_kind == "lever" }.each do |tool|
          result << Choice.new(kind: "pry", connection: edge, tool: tool)
        end
      end
    end
    result
  end

  def find(token) = choices.find { |choice| choice.token == token }

  def apply!(proposed)
    Item.transaction do
      choice = find(proposed&.token)
      return Result.new(status: "rejected", fact: "That physical action is unavailable. No item or passage changed.") unless choice

      case choice.kind
      when "consume"
        before = playthrough.condition&.hp
        if before.nil? && choice.item.healing_points.positive?
          return Result.new(status: "rejected", fact: "Your condition is unavailable, so the healing item was not consumed.")
        end
        Playthrough::Turn.new(playthrough).mend!(playthrough.character, choice.item.healing_points)
        gained = before ? playthrough.condition.hp - before : 0
        spend!(choice.item, "consumed")
        Result.new(status: "applied", fact: "You consumed #{choice.item.name}. It is gone from your possessions. You recovered #{gained} hit points.")
      when "burn"
        spend!(choice.item, "burned")
        Result.new(status: "applied", fact: "You burned #{choice.item.name} using #{choice.tool.name}. The burned item is gone; you still carry #{choice.tool.name}.")
      when "unlock", "pick", "pry", "force"
        open_passage!(choice)
      else
        # An offer is a conversation. Only the recipient's closed acceptance
        # choice can transfer it; calling this writer cannot force a gift.
        Result.new(status: "rejected", fact: "The item remains in your hands until its recipient accepts it.")
      end
    end
  end

  private

  def spend!(item, disposition)
    item.update!(disposition: disposition, character: nil, location: nil, **Location::Placement.unplaced)
  end

  def open_passage!(choice)
    check = unless choice.kind == "unlock"
      ability = choice.kind == "pick" ? "dexterity" : "strength"
      Playthrough::Turn.new(playthrough).check(playthrough.character, ability, penalty: choice.kind == "force" ? 4 : 0)
    end
    if choice.kind != "unlock" && !check&.passed?
      return Result.new(status: "failed", fact: "You tried to #{choice.name.downcase}. #{check}. The way remains closed; you stay here.")
    end

    means = { "unlock" => "key", "pick" => "lockpick", "pry" => "lever", "force" => "force" }.fetch(choice.kind)
    Playthrough::Passage.open!(playthrough, choice.connection, means: means, item: choice.tool)
    Result.new(status: "applied", fact: "You opened the way to #{choice.connection.connected_location.name}.#{check ? " #{check}." : ''} You have not crossed it; you remain in #{playthrough.current_location.name}.")
  end
end
