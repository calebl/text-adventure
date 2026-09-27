# ONE STEP'S RECORDS, WRITTEN DOWN WHOLE -- the neutral half of the sweep.
#
# `EngineSweep::Expectation` asks a report the questions a script chose to ask;
# this answers every one of them at once, so two engines that play the same
# script can be compared on everything the sweep could have asserted rather
# than on what one script happened to. The keys are exactly
# `EngineSweep::Expectation::KEYS`, in that order, less the three that are
# questions about `exits` rather than facts of their own (`exits_include`,
# `exits_exclude`) and read nothing `exits` does not already hold.
#
# EVERY VALUE IS A PLAIN JSON VALUE, and every set is sorted, because the
# point is a byte-for-byte diff between an engine written in Ruby and one that
# is not: a set the Ruby side happens to return in id order is still a set,
# and an engine that returned it in another order has not diverged. Ids are
# the ones `EngineSweep::Walk::ID_BASE` pins, so they are the same wherever a
# walk is played. `shown` is nil for a step that did not render in a browser.
#
# It reads and never writes: the walk builds it before it checks the step, and
# nothing here may move a record the expectation then reads.
class EngineSweep::Dump
  KEYS = (EngineSweep::Expectation::KEYS - %w[exits_include exits_exclude]).freeze

  def initialize(report, drifts:, blows: 0, hazards: 0, elapsed_minutes: 0, shown: nil, volitions: 0, acts: 0)
    @report = report
    @counts = { "drifts" => drifts, "blows" => blows, "hazards" => hazards, "volitions" => volitions,
                "acts" => acts, "elapsed_minutes" => elapsed_minutes }
    @shown = shown
  end

  def to_h
    @to_h ||= KEYS.index_with { |key| value(key) }
  end

  private

  attr_reader :report

  def state = report.state

  def value(key)
    return @counts.fetch(key) if @counts.key?(key)

    case key
    when "location" then room(state.location)
    when "storey" then state.location&.z
    when "exits" then state.exits.map { |exit| room(exit) }.sort_by { |row| [ row["name"], row["id"] ] }
    when "here" then things(state.items_here)
    when "carrying" then things(state.carried)
    when "present" then people(state.present)
    when "foes" then people(state.foes)
    when "inscription" then inscriptions
    when "hp" then state.condition&.hp
    when "hp_of" then hit_points
    when "abilities" then abilities
    when "dead" then state.over
    when "changed" then report.changed?
    when "change" then report.change
    when "refused" then report.refused?
    when "offers" then report.refusal
    when "understood" then report.understood
    when "resolved_by" then report.resolved_by
    when "note" then Array(report.note).join("\n").presence
    when "quest" then state.arc.map { |position, beat, _summary| [ position.to_s, beat ] }.sort_by { |position, _| position.to_i }.to_h
    when "ending" then state.ending || "none"
    when "ending_words" then state.ending_words.presence
    when "scheduled" then state.scheduled
    when "fired" then state.fired
    when "shown" then @shown
    else raise ArgumentError, "no dump for #{key.inspect}"
    end
  end

  def room(location)
    return nil if location.nil?

    { "id" => location.id, "name" => location.name, "detail" => location.detail_level }
  end

  def things(items) = items.map { |item| { "id" => item.id, "name" => item.name } }.sort_by { |row| [ row["name"], row["id"] ] }

  def people(characters)
    characters.map { |person| { "id" => person.id, "name" => person.fullname } }.sort_by { |row| [ row["name"], row["id"] ] }
  end

  # What is written on everything in reach that has writing or could, the
  # same reach `inscription:` looks in; `text` is nil for a readable thing
  # left blank. A list rather than a mapping by name, because two things in
  # reach may share one.
  def inscriptions
    (state.items_here + state.carried).select { |item| item.readable? || item.inscription.present? }
                                      .map { |item| { "id" => item.id, "name" => item.name, "text" => item.inscription.presence } }
                                      .sort_by { |row| [ row["name"], row["id"] ] }
  end

  # Everybody standing here with a stat block, by full name.
  def hit_points
    state.present.filter_map { |person| [ person.fullname, state.conditions[person.id].hp ] if state.conditions[person.id] }
         .sort.to_h
  end

  def abilities
    who = state.character
    return nil if who.nil?

    Character::ABILITIES.to_h { |ability| [ ability.to_s, who[ability.to_s] ] }
  end
end
