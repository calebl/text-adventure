# WHETHER THIS GAME IS IN A FIGHT, WHEN THAT FIGHT IS OVER, AND THE ONE `Scene`
# THAT CLOSES IT.
#
# WHY A FIGHT IS NOT A SCENE PER ROUND. `Story#clock` is
# `MAX(scenes.story_timestamp)` and `Scene` validates a description, so
# ANYTHING that costs story time has to write a row of text into the column
# `Story::Audit`, `Eval::Richness` and both frozen corpora read as NARRATION
# (`Playthrough::Refusal`'s header states the rule). A Scene per round would put
# a paragraph of engine copy in there once per exchange; writing no Scene at all
# would leave the story's clock standing still through a fight, which is a lie
# the world's own mechanics would then act on (`WorldMechanic`). So:
#
#   THE EXCHANGE       `playthrough_blows`, one durable row per blow, written by
#                      `Playthrough::Turn#strike!` and read by nothing else.
#   THE FIGHT          ONE `Scene`, here, when it ENDS: `resolved_action:
#                      "attack"`, `acted_on:` the foe, `story_timestamp`
#                      advanced by `Scene::TURN_MINUTES["action"]` times the
#                      rounds it took, and a description that is the ENGINE's
#                      own sentence and never a model's.
#
# `Scene#engine_authored?` is true of it, and `Story::Audit` and
# `Eval::Richness` skip it -- so the audit's exposure to engine copy is one row
# per fight rather than one per round, and `rake game:score` prints the count it
# excluded so the exclusion cannot hide.
#
# WHEN A FIGHT IS OVER, and it is exactly three things:
#
#   nobody left to fight   no live foe is standing in the room it happened in.
#                          `Playthrough#foes_in` is the reader, so "left to
#                          fight" means the world's hostile AND this game's
#                          provoked, minus this game's dead.
#   the party left         the playthrough is standing somewhere else. The
#                          captain's call C1: a fight is always escapable by
#                          leaving the room, and this is that call written down.
#                          The foes in the room you LEFT act before you go
#                          (`Playthrough::Riposte`) and then it is over.
#   the player died        `playthroughs.ended_at` is set. Nothing will ever
#                          change again, so the fight is closed and the last
#                          thing in the log says how it ended.
#
# THE OPEN FIGHT IS A RECORD AND NOT A FLAG: it is the blows with no closing
# Scene (`Playthrough::Blow.open`). There is no `fighting` column to go stale,
# no `engaged_at` to disagree with the room somebody is standing in, and a
# process that died mid-fight leaves a database that reads correctly.
class Playthrough::Fight
  attr_reader :playthrough

  def initialize(playthrough)
    @playthrough = playthrough
  end

  # THE BLOWS NO CLOSING SCENE HAS CLAIMED, oldest first: the fight that is
  # still on. Not memoized -- `#close!` is asked at the end of the same turn
  # `Playthrough::Turn#strike!` wrote into it.
  def open_blows = playthrough.blows.open.chronological.includes(:attacker, :target).to_a

  def on? = playthrough.blows.open.exists?

  # WHICH TURN OF THE FIGHT THE NEXT BLOW LANDS ON, OUT OF A RECORD.
  #
  # A ROUND IS A TURN -- the captain's call C5 -- so this is read ONCE per turn,
  # by `Playthrough::Turn#play` and `Playthrough::Mechanics#run`, and handed to
  # every blow that turn strikes: the player's own and each of the riposte's, so
  # one exchange is one round however many people were in it. Off the rows and
  # not off a counter, for the reason `Playthrough::Blow.next_sequence` is:
  # a number in memory does not survive the process that held it.
  def next_round = playthrough.blows.open.maximum(:round).to_i + 1

  # WHERE THE FIGHT IS HAPPENING: the room the first open blow landed in. A
  # column on the row rather than the attacker's whereabouts, because the party
  # carries none -- `characters.location_id` is nil for every blow the player
  # throws.
  def room = open_blows.first&.location

  # HOW MANY TURNS IT HAS TAKEN, which is what the closing Scene's story time is
  # `Scene::TURN_MINUTES["action"]` times. Distinct rounds and not the blow
  # count: three foes swinging in one turn is one round.
  def rounds = open_blows.map(&:round).uniq.size

  # WHO THE FIGHT WAS WITH, for `scenes.acted_on`. The person the PLAYER last
  # swung at, because that is the one the player named; whoever last swung at
  # the player when the player never swung at all (a monster that opened the
  # fight itself, which nothing does yet).
  def opponent
    blows = open_blows
    party = playthrough.character

    blows.reverse.find { |blow| blow.attacker_id == party&.id }&.target || blows.last&.attacker
  end

  # WHETHER THE FIGHT HAS ENDED. False when there is no fight at all, which is
  # every turn of every game that has never swung at anybody.
  def over?
    blows = open_blows
    return false if blows.empty?
    return true if playthrough.over?
    return true unless playthrough.current_location_id == blows.first.location_id

    playthrough.foes_in(blows.first.location).empty?
  end

  # THE ONE SCENE, WRITTEN ONCE, AND NIL WHEN THERE IS NOTHING TO CLOSE.
  #
  # It stamps every open blow with itself, which is what takes the fight off
  # `Playthrough::Blow.open` -- so this is idempotent by the records: a second
  # call has no open blows and writes nothing.
  #
  # NO MODEL CALL, EVER, IN EITHER MODE. The description is `#sentence`, the
  # engine's own words about what its own dice did, so `rake game:mechanics`
  # and the browser close a fight identically and `rake game:sweep` walks the
  # whole of it with `BaseAgent.new` replaced by something that raises.
  def close!
    blows = open_blows
    return nil if blows.empty? || !over?

    here = blows.first.location
    scene = nil

    Scene.transaction do
      scene = Scene.create!(
        story: playthrough.story,
        location: here,
        previous_scene: playthrough.current_scene,
        description: sentence(blows, here),
        summary: summary(blows, here),
        story_timestamp: playthrough.story_now + (Scene::TURN_MINUTES.fetch("action") * blows.map(&:round).uniq.size).minutes,
        resolved_action: "attack",
        acted_on: opponent,
        characters: playthrough.cast_in(here)
      )
      Playthrough::Blow.where(id: blows.map(&:id)).update_all(scene_id: scene.id)
      playthrough.update!(current_scene: scene)
    end

    scene
  end

  # THE ENGINE'S OWN SENTENCE, and it is the engine's for the reason
  # `Playthrough::Refusal`'s and `Playthrough::DeathNotice`'s are: the app is
  # talking about what the app's own dice did, and there is nothing here for a
  # narrator to decide. Every number in it is off a row.
  def sentence(blows, here)
    [ "The fight in #{here.name} is over after #{count(blows.map(&:round).uniq.size, "round")}.",
      ending(blows),
      "#{count(blows.size, "blow")} landed: #{blows.map { |blow| blow.to_s }.join("; ")}." ].compact.join(" ")
  end

  def summary(blows, here)
    "A fight in #{here.name}: #{count(blows.size, "blow")} over " \
      "#{count(blows.map(&:round).uniq.size, "round")}. #{ending(blows)}"
  end

  private

  # HOW IT ENDED, and the three endings are the three halves of `#over?` read
  # back out -- so what the player is told and what the engine decided cannot
  # come apart.
  def ending(blows)
    party = playthrough.character
    # WHO IS DEAD NOW, asked of `Playthrough#vitals_for` -- the one reader --
    # rather than of the blows' own `hp_after`. A body can reach zero on a turn
    # no blow of this fight took it there (`harm 5` is an engine instrument and
    # a hazard will be a mechanic), and a closing sentence that read only its
    # own rows would say nobody was killed while the body was on the floor.
    dead = ([ party ] + blows.flat_map { |blow| [ blow.attacker, blow.target ] })
             .compact.uniq.select { |person| playthrough.vitals_for(person)&.dead? }

    return "#{party.fullname} is dead." if party && dead.include?(party)
    return "#{dead.map(&:fullname).to_sentence} is dead." if dead.one?
    return "#{dead.map(&:fullname).to_sentence} are dead." if dead.many?

    "Nobody was killed: the party is no longer standing in it."
  end

  def count(number, noun) = "#{number} #{noun}#{"s" unless number == 1}"
end
