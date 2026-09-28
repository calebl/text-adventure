# The arrival bench's staged arrival, with the reactions a case names held on
# it inside the same rollback. The rows are the ones the engine's reactions
# step would have written, with the engine's own facts: a word is the first
# thing of its kind the engine offers the person (`Eval::HeldSpeech`), and an
# act is the first act of its shape `Playthrough::Volition` offers, applied by
# it. Both are offered and applied with the party counted as standing in the
# room, as the engine counts it while the people there react, and the game is
# stood back in the room it is coming from before the request is built.
class Eval::Arrival::Reactions::Stage < Eval::Arrival::Stage
  # The heads of what may be said, as the engine's `speak:` tokens start.
  SAID = %w[greet warn ask demand dismiss].freeze

  attr_reader :reactions

  def build!
    super
    people!
    @reactions = react!
    @generator = Scene::Generator.new(room, previous_scene: @previous, playthrough: game, reactions: reactions)
  end

  # THE ARRIVAL REQUEST THE ENGINE BUILDS, naming the rows held as this
  # arrival's reactions.
  def request
    Playthrough::Requests.build(:arrival, playthrough: game.id, location: room.id, previous_scene: @previous.id,
                                          opening: false, reactions: reactions)
  end

  def facts
    super.merge("reactions" => game.volitions.where(id: reactions).order(:id).map do |row|
      { "who" => row.character.fullname, "chosen" => row.chosen.sub(/:-?\d+\z/, ""), "status" => row.status, "fact" => row.fact }
    end)
  end

  private

  # Everybody the case names, in the room with a pursuit to react from: Maren,
  # and a second resident where the case has one. A foe is Maren, hostile.
  def people!
    resident.update!(desire_pursuit: kase.fetch("pursuit", "attend"), hostile: kase["hostile"] == true)
    if kase["second"]
      person(920003, "Tobin Reyes", "Tobin").update!(desire_pursuit: kase.fetch("second"))
    end
    room.update!(hazard: "flooded", hazard_die: 4) if kase["hazard"]
    return unless kase["holding"]

    game.items.find_by!(name: "brass key").update!(location: nil, character: resident)
  end

  def react!
    game.update!(current_location: room)
    ids = kase.fetch("reactions").map do |name, act|
      who = story.characters.find_by!(fullname: name)
      SAID.include?(act.split(":").first) ? Eval::HeldSpeech.say!(game.reload, who, act, location: room).id : act!(who, act)
    end
    game.update!(current_location: origin)
    game.reload
    ids
  end

  def act!(who, act)
    volition = Playthrough::Volition.new(game.reload, who, location: room)
    token = volition.choices.keys.find { |offered| offered == act || offered.start_with?("#{act}:") } or
      raise ArgumentError, "#{kase.fetch('id')}: #{who.fullname} is offered no #{act.inspect} in #{room.name}"
    volition.apply!(token)
    game.volitions.where(character: who).order(:id).last.id
  end
end
