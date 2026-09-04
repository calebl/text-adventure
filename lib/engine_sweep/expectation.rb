# WHAT THE RECORDS SHOULD SAY AFTER ONE TYPED LINE, and the whole of what a
# script is allowed to assert.
#
# EVERY KEY IS A FACT OFF THE RECORDS, never a fact about prose: there is no
# prose in this mode, and a sweep that started reading text would be a worse
# copy of `Story::Audit`. What is here is where the player stands, what leads
# out of there and whether each of those is written yet, what is lying in the
# room, what is in the player's hands, and what the engine said it did or would
# not do.
#
#   location        the room, optionally "Name (stub)" or "Name (realized)"
#   exits           the WHOLE set of ways out, in any order, each optionally
#                   carrying its detail level the same way
#   exits_include   some of them, for a script that does not want to pin the rest
#   exits_exclude   names that must NOT lead out of here -- the shape of an
#                   invented door
#   here            the whole set of item names lying in this room
#   carrying        the whole set of item names the player holds
#   present         the whole set of people standing here, by full name -- the
#                   closed set `talk` resolves against (`Character.present_in`),
#                   minus the player themselves
#   hp              the player's current hit points, exactly -- read through
#                   `Playthrough#vitals_for`, never off the printed read-out
#   abilities       the player's three abilities, as a mapping of
#                   strength/dexterity/will to the exact score -- read off the
#                   `Character` columns, never off the printed read-out, and a
#                   script may name one, two or all three. It is ONE key rather
#                   than three because they are one fact the world holds about a
#                   body, and because `Character::ABILITIES` is what a reader
#                   iterates everywhere else
#   dead            whether the playthrough is over: `playthroughs.ended_at` is
#                   set, which since the captain's ruling of 2026-09-04 happens
#                   for exactly one reason and stays true for ever
#   inscription     what the records say is written on a named thing -- a
#                   mapping of item name to text the stored inscription has to
#                   contain, or to `false` for a thing with no writing on it.
#                   Read off `Item#inscription`, never off anything printed
#   changed         whether the engine wrote something
#   change          text the one-line diff of that write has to contain, which
#                   is how a script pins that a stub was walked into as a stub
#   refused         whether the line was refused
#   offers          text the refusal has to contain, which is how a script pins
#                   that a refusal named what WOULD have worked
#   understood      the engine's own reading of the line, exactly
#   note            text the note has to contain
#   drifts          `Playthrough::Drift` rows this line wrote
#
# `KEYS` IS CLOSED AND UNKNOWN KEYS RAISE. A misspelt expectation that was
# quietly ignored would read as a passing step, which is the one failure mode a
# test fixture must not have.
class EngineSweep::Expectation
  KEYS = %w[
    location exits exits_include exits_exclude here carrying present inscription
    hp abilities dead changed change refused offers understood note drifts
  ].freeze

  # "The Vestry Hulk (stub)" -> the name and the detail level it has to be in.
  # A bare name asserts nothing about whether the room is written.
  Named = Data.define(:name, :detail) do
    def to_s = detail ? "#{name} (#{detail})" : name
  end

  DETAIL_LEVELS = %w[stub realized].freeze

  # One thing that did not hold: which expectation, what the script asked for,
  # what the records said. Rendered by `EngineSweep::Result::Failure`, which
  # adds the script and the step.
  Unmet = Data.define(:key, :expected, :actual)

  attr_reader :document

  def self.read(document, where)
    return new({}) if document.nil?
    raise EngineSweep::InvalidScript, "#{where}: \"expect\" is not a mapping" unless document.is_a?(Hash)

    unknown = document.keys - KEYS
    raise EngineSweep::InvalidScript, "#{where}: unknown expectation(s) #{unknown.inspect}. There is: #{KEYS.join(", ")}" if unknown.any?

    new(document, where: where)
  end

  def initialize(document, where: nil)
    @document = document
    @where = where
    validate!
  end

  # EVERY UNMET EXPECTATION, not the first: a step that moved to the wrong room
  # is usually holding the wrong things too, and seeing both is how the cause
  # gets found in one pass instead of three.
  def check(report, drifts:)
    state = report.state

    [
      check_location(state),
      check_exits(state),
      check_items("here", state.items_here),
      check_items("carrying", state.carried),
      check_people("present", state.present),
      check_inscriptions(state),
      check_equals("hp", state.condition&.hp),
      check_abilities(report),
      check_flag("dead", state.over),
      check_flag("changed", report.changed?),
      check_contains("change", report.change),
      check_flag("refused", report.refused?),
      check_contains("offers", report.refusal),
      check_equals("understood", report.understood),
      check_contains("note", Array(report.note).join("\n")),
      check_equals("drifts", drifts)
    ].flatten.compact
  end

  private

  attr_reader :where

  def validate!
    validate_abilities!
    validate_inscriptions!
    Array(document["exits"]).each { |entry| named(entry) }
    Array(document["exits_include"]).each { |entry| named(entry) }
    Array(document["exits_exclude"]).each { |entry| named(entry) }
    named(document["location"]) if document.key?("location")
  end

  # A mapping of one of the three abilities to an integer, and nothing else --
  # for the same reason `KEYS` is closed. A misspelt ability would look like an
  # expectation and assert nothing at all, which is the one failure mode a
  # fixture must not have.
  def validate_abilities!
    return unless document.key?("abilities")

    wanted = document["abilities"]
    unless wanted.is_a?(Hash)
      raise EngineSweep::InvalidScript,
            "#{where}: \"abilities\" is a mapping of #{Character::ABILITIES.join("/")} to a score, " \
            "got #{wanted.inspect}"
    end

    unknown = wanted.keys.map(&:to_s) - Character::ABILITIES.map(&:to_s)
    if unknown.any?
      raise EngineSweep::InvalidScript,
            "#{where}: \"abilities\" names #{unknown.inspect}; there is: #{Character::ABILITIES.join(", ")}"
    end

    wanted.each_value do |score|
      next if score.is_a?(Integer)

      raise EngineSweep::InvalidScript, "#{where}: an \"abilities\" entry is a whole score, got #{score.inspect}"
    end
  end

  # A mapping and nothing else, for the same reason `KEYS` is closed: a list of
  # item names here would look like an expectation and assert nothing.
  def validate_inscriptions!
    return unless document.key?("inscription")

    wanted = document["inscription"]
    unless wanted.is_a?(Hash)
      raise EngineSweep::InvalidScript,
            "#{where}: \"inscription\" is a mapping of item name to the text it must contain " \
            "(or to false for a thing with nothing written on it), got #{wanted.inspect}"
    end

    wanted.each_value do |expected|
      next if expected == false || expected.is_a?(String)

      raise EngineSweep::InvalidScript,
            "#{where}: an \"inscription\" entry is text to look for or false, got #{expected.inspect}"
    end
  end

  def named(entry)
    raise EngineSweep::InvalidScript, "#{where}: #{entry.inspect} is not a name" unless entry.is_a?(String)

    match = entry.match(/\A(?<name>.+?)\s*\((?<detail>[a-z]+)\)\z/)
    return Named.new(name: entry.strip, detail: nil) if match.nil?

    detail = match[:detail]
    unless DETAIL_LEVELS.include?(detail)
      raise EngineSweep::InvalidScript,
            "#{where}: #{entry.inspect} asks for detail level #{detail.inspect}; there is: #{DETAIL_LEVELS.join(", ")}"
    end

    Named.new(name: match[:name], detail: detail)
  end

  def check_location(state)
    return nil unless document.key?("location")

    wanted = named(document["location"])
    actual = state.location.nil? ? nil : Named.new(name: state.location.name, detail: state.location.detail_level)

    return unmet("location", wanted, actual) if actual.nil? || actual.name != wanted.name
    return unmet("location", wanted, actual) if wanted.detail && wanted.detail != actual.detail

    nil
  end

  def check_exits(state)
    actual = state.exits.map { |exit| Named.new(name: exit.name, detail: exit.detail_level) }

    [
      check_whole_set("exits", actual),
      check_subset("exits_include", actual),
      check_absent("exits_exclude", actual)
    ]
  end

  def check_whole_set(key, actual)
    return nil unless document.key?(key)

    wanted = Array(document[key]).map { |entry| named(entry) }
    return unmet(key, wanted, actual) if wanted.map(&:name).sort != actual.map(&:name).sort

    check_details(key, wanted, actual)
  end

  def check_subset(key, actual)
    return nil unless document.key?(key)

    wanted = Array(document[key]).map { |entry| named(entry) }
    missing = wanted.map(&:name) - actual.map(&:name)
    return unmet(key, wanted, actual) if missing.any?

    check_details(key, wanted, actual)
  end

  def check_absent(key, actual)
    return nil unless document.key?(key)

    wanted = Array(document[key]).map { |entry| named(entry) }
    present = wanted.map(&:name) & actual.map(&:name)
    return nil if present.empty?

    unmet(key, "none of #{wanted.map(&:to_s).join(", ")}", actual)
  end

  # Only the entries that asked for one. A script that names an exit without
  # saying whether it is written is asserting the door, not the room.
  def check_details(key, wanted, actual)
    wrong = wanted.select do |entry|
      entry.detail && actual.find { |candidate| candidate.name == entry.name }&.detail != entry.detail
    end
    return nil if wrong.empty?

    unmet(key, wanted, actual)
  end

  def check_items(key, records)
    return nil unless document.key?(key)

    wanted = Array(document[key]).map(&:to_s)
    actual = records.map(&:name)
    return nil if wanted.sort == actual.sort

    unmet(key, wanted, actual)
  end

  # WHO IS STANDING HERE, by full name. A separate reader from `#check_items`
  # only because a person answers to `fullname` where a thing answers to
  # `name` -- it is the same whole-set comparison, over the same kind of closed
  # set, and an offline walk can assert it because presence is a record now
  # rather than something reconstructed from a scene an offline walk never
  # writes.
  def check_people(key, records)
    return nil unless document.key?(key)

    wanted = Array(document[key]).map(&:to_s)
    actual = records.map(&:fullname)
    return nil if wanted.sort == actual.sort

    unmet(key, wanted, actual)
  end

  # WHAT IS WRITTEN ON A THING, off the row and not off the screen.
  #
  # The one expectation here that reads a column rather than a set, and it is a
  # column rather than the printed line on purpose: `Playthrough::Mechanics`
  # prints an inscription as a note, so a script asserting the note would be
  # asserting that the read-out is wired up. This asserts what the ENGINE holds,
  # which is the thing that must not drift between two readings -- and a script
  # that reads the same note twice and expects the same text twice is then
  # making a claim the records have to keep.
  #
  # The item is looked for in both sets a read resolves against, here and in the
  # player's hands, because reading does not care which. A name that matches
  # nothing is unmet rather than skipped: a typo must not read as a pass.
  def check_inscriptions(state)
    return nil unless document.key?("inscription")

    wanted = document["inscription"]
    records = state.items_here + state.carried

    wanted.filter_map do |name, expected|
      item = records.find { |record| record.name == name }
      next unmet("inscription", "#{name}: #{render(expected)}", "no #{name} here or in hand") if item.nil?

      check_one_inscription(name, expected, item)
    end
  end

  # `false` means the thing has no writing on it at all; anything else is text
  # the stored inscription has to contain.
  def check_one_inscription(name, expected, item)
    if expected == false
      return nil unless item.readable? || item.inscription.present?

      return unmet("inscription", "#{name}: nothing written on it", "#{name}: #{item.inscription.inspect}")
    end

    return nil if item.inscription.to_s.include?(expected.to_s)

    unmet("inscription", "#{name}: text containing #{expected.to_s.inspect}",
          "#{name}: #{item.inscription.presence.inspect || "nothing written down"}")
  end

  # WHAT THE WORLD SAYS THE PLAYER'S ABILITIES ARE, off the columns and not off
  # the screen -- the same rule `#check_inscriptions` is under and for the same
  # reason: a script asserting the printed sheet would be asserting that the
  # read-out is wired up, and what must not drift is what the ENGINE holds.
  #
  # Only the abilities the script names. A step that pins one is making a claim
  # about that one, which is what lets a walk say "the file's strength survived
  # everything typed at it" without restating the whole sheet.
  def check_abilities(report)
    return nil unless document.key?("abilities")

    who = report.state.character
    return [ unmet("abilities", document["abilities"], "no protagonist") ] if who.nil?

    document["abilities"].filter_map do |ability, expected|
      actual = who[ability.to_s]
      next if actual == expected

      unmet("abilities", "#{ability}: #{expected}", "#{ability}: #{actual.nil? ? "none" : actual}")
    end
  end

  def check_flag(key, actual)
    return nil unless document.key?(key)
    return nil if document[key] == actual

    unmet(key, document[key], actual)
  end

  def check_equals(key, actual)
    return nil unless document.key?(key)
    return nil if document[key] == actual

    unmet(key, document[key], actual)
  end

  # Substrings rather than the whole line, because these are sentences written
  # for a player to read and a script that pinned them word for word would
  # break on every wording change without a defect anywhere.
  def check_contains(key, text)
    return nil unless document.key?(key)

    missing = Array(document[key]).reject { |wanted| text.to_s.include?(wanted) }
    return nil if missing.empty?

    unmet(key, "text containing #{missing.map(&:inspect).join(", ")}", text.presence || "nothing")
  end

  def unmet(key, expected, actual)
    Unmet.new(key: key, expected: render(expected), actual: render(actual))
  end

  def render(value)
    case value
    when Array then value.empty? ? "nothing" : value.map(&:to_s).join(", ")
    when nil then "nothing"
    else value.to_s
    end
  end
end
