# ONE STORED WALK: which world, what gets typed, and what the records should
# say afterwards.
#
# IT IS A FIXTURE, NOT A LANGUAGE. There is no branching, no variables and no
# way to compute anything -- a step is a line somebody could have typed and a
# block of facts somebody could have read off the screen. Everything a script
# can assert is in `Expectation::KEYS` and a key outside that list raises, so a
# typo cannot turn into an expectation that silently holds.
#
# THE SHAPE:
#
#   story: The Salt Assizes          # a seeded world, by title
#   steps:
#   - type: drop the tide-slate      # what the player typed
#     expect:
#       changed: true
#       location: The Causeway Court (realized)
#       here: [Assize tide-slate]
#       carrying: []
#
# `id` and `why` are optional on a step: the first names it in a failure, the
# second says what the step is for. Neither is asserted.
#
# `player` IS THE ONE THING THAT IS NOT ONE LINE SOMEBODY TYPED, and it exists
# because the defect it regression-tests needs two people playing one world:
# the party's inventory belongs to the playthrough, so a script has to be able
# to type into a second one and read back what IT is holding. A step with no
# `player` goes to the default, so every existing script is one playthrough and
# unchanged.
#
#   - type: take the ward stamp   # the default player
#   - type: look
#     player: second              # a second playthrough of the same world
#     expect:
#       carrying: [Ward Office 12 daybook]
#
# `reseed: true` IS THE OTHER THING THAT IS NOT ONE LINE SOMEBODY TYPED, and it
# is here for the same kind of reason: re-seeding a world somebody is PLAYING is
# a thing the captain does daily and nothing walked it. A step with it re-loads
# the world file over the copy this walk has been playing -- the same
# `WorldSeed::Loader` call `bin/rails db:seed` makes -- and then reads the
# records back with nothing else having happened, so every expectation below it
# is a statement about what a re-seed did or did not disturb. What the loader
# reconciled and what it warned about are in the step's `note`, so a script can
# pin the reconciliation itself and not just its effect.
#
#   - type: take the ward stamp
#   - reseed: true
#     expect:
#       carrying: []              # the file put the stamp back on the floor
#       here: [ward stamp]
#
# A step carries `type` or `reseed`, never both and never neither.
#
# `browser:` PLAYS ONE SUBMISSION THE WAY THE BROWSER DOES, with a token and
# fixed provider answers, and `accepted_first` is what the player typed while
# an earlier turn was still running -- accepted, enqueued, and not yet played.
# The step then delivers the LATER job first, which is the race
# `config/queue.yml`'s three worker threads make reachable:
#
#   - type: /move Courtyard
#     browser:
#       token: move
#       accepted_first:
#       - { token: pickup, type: /take red coin }
#     expect:
#       carrying: [red coin]        # the earlier line still played first
#       location: Courtyard (realized)
#
# `reseed:` MAY NAME A DIFFERENT VERSION OF THE FILE, which is what lets the
# walk reach the defect rather than only the rule. A rename is what the SECOND
# version of a seed file says, and before `WorldSeed.natural_key` a renamed room
# was a room that did not exist yet -- so re-seeding created a second one beside
# the first and the office opened onto both. A mapping says which names this
# load writes, and nothing else about the file changes:
#
#   - reseed:
#       locations: { The Supply Closet: Supply Closet }
#       items: { ward stamp: Ward Stamp }
#
# It is still a fixture rather than a language: the mapping says which version
# of the file is being loaded, the way `story:` says which file. The invariants
# after the walk are then checked against the file AS LAST LOADED, so a rename
# does not read as an invented doorway.
class EngineSweep::Script
  # Whose game a step with no `player` is typed into.
  DEFAULT_PLAYER = "first"

  # npc_action supplies one fixed character choice on a talk turn. It replaces
  # the model's decision, never the engine writer: Conversation applies it
  # through the same NpcAction gate as InteractionAgent before the riposte.
  Step = Data.define(:index, :id, :typed, :why, :player, :reseed, :npc_action, :browser, :expectation) do
    # How a step is named when it fails. The number is always there because a
    # script may type the same line twice on purpose.
    def label = "step #{index}#{" #{id}" if id.present?}#{" (#{player})" unless player == DEFAULT_PLAYER}"

    def reseed? = !reseed.nil?

    # `{ "locations" => {...}, "items" => {...} }`, and empty for a plain
    # `reseed: true` -- the same file loaded again.
    def renames = reseed.is_a?(Hash) ? reseed : {}
  end

  attr_reader :path, :story, :steps, :why

  def self.load(path)
    document = YAML.safe_load_file(path)
    raise EngineSweep::InvalidScript, "#{path}: expected a mapping" unless document.is_a?(Hash)

    new(path: path,
        story: fetch!(document, "story", path),
        why: document["why"],
        steps: read_steps(fetch!(document, "steps", path), path))
  rescue Psych::Exception => e
    raise EngineSweep::InvalidScript, "#{path}: #{e.message}"
  end

  def self.fetch!(document, key, path)
    document.fetch(key) { raise EngineSweep::InvalidScript, "#{path}: no #{key.inspect}" }
  end

  def self.read_steps(rows, path)
    raise EngineSweep::InvalidScript, "#{path}: \"steps\" is not a list" unless rows.is_a?(Array)

    rows.each_with_index.map do |row, offset|
      raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} is not a mapping" unless row.is_a?(Hash)

      unknown = row.keys - %w[id type why player reseed npc_action browser expect]
      raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} has unknown key(s) #{unknown.inspect}" if unknown.any?

      reseed = read_reseed(row["reseed"], "#{path}: step #{offset + 1}") if row.key?("reseed")

      if reseed && row.key?("type")
        raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} is both a typed line and a `reseed`, and it can only be one"
      end
      unless reseed || row.key?("type")
        raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} has no \"type\" and is not a `reseed`"
      end
      if row.key?("npc_action") && (!row["npc_action"].is_a?(String) || row["npc_action"].blank? || reseed)
        raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} npc_action must be a nonempty choice on a typed line"
      end
      browser = read_browser(row["browser"], "#{path}: step #{offset + 1}") if row.key?("browser")
      if browser && (reseed || row.key?("npc_action"))
        raise EngineSweep::InvalidScript, "#{path}: step #{offset + 1} browser cannot combine with reseed or npc_action"
      end

      Step.new(index: offset + 1, id: row["id"], typed: row["type"], why: row["why"],
               player: row["player"].presence || DEFAULT_PLAYER, reseed: reseed, npc_action: row["npc_action"], browser: browser,
               expectation: EngineSweep::Expectation.read(row["expect"], "#{path}: step #{offset + 1}"))
    end
  end

  # A browser submission with a failed renderer, a duplicate token, or ordered
  # fixed provider replies. A realization walk can fail after its paid detail
  # and assert its retry consumes only exits. `raises` means an unavailable
  # provider interrupts the submission instead of producing an engine fallback.
  #
  # `accepted_first` is the lines the browser accepted BEFORE this one whose
  # jobs have not been delivered yet -- what the player typed while a turn was
  # running. It is the only way a walk can reach the case where a later job
  # takes the lock first, which is the whole of what it exists for.
  def self.read_browser(value, where)
    unless value.is_a?(Hash) && (value.keys - %w[token fail replies raises realizes accepted_first]).empty? && value["token"].is_a?(String) && value["token"].present?
      raise EngineSweep::InvalidScript, "#{where}: browser expects a token and optional fail: narration or arrival"
    end
    if value.key?("accepted_first")
      unless value["accepted_first"].is_a?(Array) && value["accepted_first"].any?
        raise EngineSweep::InvalidScript, "#{where}: browser accepted_first is a nonempty list of earlier submissions"
      end
      value["accepted_first"].each do |earlier|
        unless earlier.is_a?(Hash) && (earlier.keys - %w[token type]).sort.empty? &&
            earlier["token"].is_a?(String) && earlier["token"].present? &&
            earlier["type"].is_a?(String) && earlier["type"].present?
          raise EngineSweep::InvalidScript, "#{where}: browser accepted_first entry needs a token and a type"
        end
      end
    end
    unless value["fail"].nil? || %w[narration arrival].include?(value["fail"])
      raise EngineSweep::InvalidScript, "#{where}: browser fail must be narration or arrival"
    end
    if value.key?("replies")
      unless value["fail"].nil? && value["replies"].is_a?(Array)
        raise EngineSweep::InvalidScript, "#{where}: browser replies is a list and cannot combine with fail"
      end
      value["replies"].each do |reply|
        unless reply.is_a?(Hash) && (reply.keys - %w[purpose content unavailable]).empty? &&
            %w[location narration arrival].include?(reply["purpose"]) &&
            ((reply.key?("content") && !reply.key?("unavailable")) || (reply["unavailable"] == true && !reply.key?("content")))
          raise EngineSweep::InvalidScript, "#{where}: browser reply needs a purpose and either content or unavailable: true"
        end
      end
    end
    if value.key?("raises") && (value["raises"] != true || !value["replies"]&.any? { |reply| reply["unavailable"] })
      raise EngineSweep::InvalidScript, "#{where}: browser raises requires an unavailable reply"
    end
    if value.key?("realizes") && (!value["realizes"].is_a?(String) || value["realizes"].blank? ||
        !value["replies"]&.any? { |reply| reply["purpose"] == "location" })
      raise EngineSweep::InvalidScript, "#{where}: browser realizes names one room and requires a location reply"
    end
    value
  end

  # `true` for the same file again, or a mapping of what this load renames.
  # Closed, like `Expectation::KEYS`: a misspelt `location:` here would read as
  # a plain re-seed and the step would assert the wrong thing quietly.
  RENAMEABLE = %w[locations items].freeze

  def self.read_reseed(value, where)
    return true if value == true
    raise EngineSweep::InvalidScript, "#{where}: \"reseed\" is `true` or a mapping of #{RENAMEABLE.join(" / ")}, got #{value.inspect}" unless value.is_a?(Hash)

    unknown = value.keys - RENAMEABLE
    raise EngineSweep::InvalidScript, "#{where}: \"reseed\" has unknown key(s) #{unknown.inspect}. There is: #{RENAMEABLE.join(", ")}" if unknown.any?

    value.each_value do |mapping|
      raise EngineSweep::InvalidScript, "#{where}: a \"reseed\" rename is a mapping of old name to new name, got #{mapping.inspect}" unless mapping.is_a?(Hash)
    end

    value
  end

  private_class_method :fetch!, :read_steps, :read_reseed, :read_browser

  def initialize(path:, story:, steps:, why: nil)
    @path = path
    @story = story
    @steps = steps
    @why = why
  end

  # The name a report calls it by: the filename without its extension, which is
  # what somebody would type to open it.
  def name = File.basename(path, ".yml")

  # Every game this script is typed into, in the order it first reaches them.
  # One for almost every script; the point of naming them is that a second one
  # is possible at all.
  def players = steps.map(&:player).uniq

  # The world file this script walks. Named from the TITLE rather than from the
  # script's own filename, so several scripts can walk one world.
  #
  # A CHECKED-IN WORLD FIRST, and one of the sweep's own second. Almost every
  # script walks a world a person can play (`db/seeds/worlds`); a script that
  # needs a world nobody ships -- a laid-out interior, which none of the three
  # flat checked-in worlds has -- names one from `EngineSweep::WORLDS` instead
  # and nothing else about it differs. The checked-in directory wins on a name
  # in both, so a sweep world can never shadow a world somebody plays.
  #
  # THE PATH IS ANSWERED WHETHER OR NOT THE FILE EXISTS: `EngineSweep::Walk`
  # reports a missing world naming the script and the path it looked for, which
  # is the message somebody who mistyped a title needs.
  def seed_file
    checked_in = WorldSeed::DIRECTORY.join("#{WorldSeed.slug(story)}.yml")
    return checked_in if File.exist?(checked_in)

    swept = EngineSweep::WORLDS.join("#{WorldSeed.slug(story)}.yml")
    File.exist?(swept) ? swept : checked_in
  end
end
