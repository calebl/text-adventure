# THE POSITION, WRITTEN OUT AS RECORDS A TYPED QUESTION CAN POINT AT.
#
# `Playthrough::Classifier`'s prompt states the room as prose under headings;
# a System One request states it as DATA, one entry per record under a key the
# answers come back naming. So this class is the same four closed sets and the
# same physical attempts, in the shape `Playthrough::Classifier::Request` asks
# questions over and `Playthrough::Classifier::Cascade` resolves answers through.
#
# EVERY MEMBERSHIP FACT COMES OUT OF `Playthrough::Classifier#offered_for` AND
# NOTHING ELSE, and that is the whole design of this file. That method is
# already the one table that says which records an action may reach -- the
# closed enum is built from it, the refusals are built from it, and a second
# list of "what a take can pick up" is exactly how the two stop agreeing. So:
#
#   * a group's MEMBERS are `#offered_for(<the group's defining intent>)`;
#   * a record's `valid_intents` are every intent whose `#offered_for` set
#     contains it -- DERIVED, never written down here. `examine` and `attack`
#     therefore appear on records without having a group of their own, because
#     neither reads a set that is only its own.
#
# `Playthrough::Classifier::StateTest` walks every intent in
# `Playthrough::IntentSchema::INTENTS` and fails if any record reachable by an
# action is missing from this state or carries the wrong intents.
#
# `aliases` IS `Character#nickname` AND NOTHING ELSE TODAY, because a nickname
# is the only second name any record in this game answers to -- it is the same
# fact `Playthrough::Classifier#find_character` matches on and the same one the
# closed enum carries twice. A place or a thing has one name. If a second alias
# source ever appears it belongs here, beside this one.
#
# WHAT IS DELIBERATELY NOT HERE: the travel notes (`(adjacent, walking)`) that
# `Playthrough::Classifier#exit_list` gives the prose prompt, and the one line of
# engine description per record. Both were measured OUT: every figure the
# cascade rests on was read off a state with neither, and adding one would be a
# change to a measured shape needing its own baseline. See EVALUATION.md.
class Playthrough::Classifier::State
  # THE STATE BLOCKS, AND THE INTENT WHOSE CLOSED SET IS EXACTLY ONE OF THEM.
  #
  # This table says only what each block is CALLED and which single intent's
  # `#offered_for` answer is its membership; it does not say what any action can
  # reach, which is the thing that must have one owner. `examine` and `attack`
  # are absent for that reason and not by oversight -- neither has a set of its
  # own (`examine` reads both item lists, `attack` reads the cast), so neither
  # names a block, and both still reach records through `valid_intents`.
  Group = Data.define(:key, :prefix, :kind, :intent)

  GROUPS = [
    Group.new(key: "ways_out", prefix: "way", kind: "way out", intent: :move),
    Group.new(key: "other_characters", prefix: "person", kind: "person present here", intent: :talk),
    Group.new(key: "available_items", prefix: "available_item", kind: "item lying here", intent: :take),
    Group.new(key: "player_items", prefix: "player_item", kind: "item the player is carrying", intent: :drop),
    Group.new(key: "physical_actions", prefix: "attempt", kind: "one complete physical action attempt", intent: :use)
  ].freeze

  attr_reader :classifier, :command

  def initialize(classifier, command)
    @classifier = classifier
    @command = command
    @offered = {}
  end

  # The state object as it is sent: one entry per record, plus where the player
  # is standing and the line they typed. Keys are the ones the questions'
  # criteria are keyed by and the ones `#record_for` resolves back.
  def to_h
    GROUPS.each_with_object(base) do |group, state|
      entries = entries_for(group)
      state[group.key] = entries if entries.any?
    end
  end

  # WHAT AN ANSWER'S KEY MEANS. `nothing` -- and anything this position never
  # offered -- is nil, which is the same answer the closed enum gives the model
  # call: the player named something that is not here.
  def record_for(key) = records.fetch(key.to_s, nil)

  # The keys, in state order, of every record one action may reach. This is what
  # a target question's options are built from, and it is `#offered_for` read
  # back through the same map the answers resolve through.
  def keys_for(action)
    offered(action).filter_map { |record| keys.fetch(record, nil) }
  end

  # Every key in the position, in state order -- the option set `also_named` is
  # asked over, which is wider than any one action's because the second name a
  # line carries need not be reachable by the intent it was read as.
  def all_keys = records.keys

  # The name a record answers to, for a criterion description. One definition,
  # out of the class that already owns it.
  def label_for(record) = Playthrough::Classifier.label_for(record)

  # Every intent whose closed set holds this record. Derived, never listed.
  def intents_for(record)
    Playthrough::IntentSchema::INTENTS.select { |intent| offered(intent).include?(record) }
  end

  # Whether one action's closed set holds this record -- `#offered_for` again,
  # read back through the memo this class already keeps rather than through a
  # second idea of what an action reaches.
  def offers?(action, record) = offered(action).include?(record)

  private

  def base
    {
      "location" => classifier.playthrough.current_location&.name || "Nowhere in particular.",
      "player_action" => command.to_s
    }
  end

  def entries_for(group)
    offered(group.intent).each_with_index.to_h do |record, offset|
      [ "#{group.prefix}_#{offset + 1}", entry_for(record, group) ]
    end
  end

  def entry_for(record, group)
    entry = { "kind" => group.kind, "name" => label_for(record) }
    nickname = record.respond_to?(:nickname) ? record.nickname.to_s.strip : ""
    entry["aliases"] = [ nickname ] if nickname.present? && nickname != entry["name"]
    entry["valid_intents"] = intents_for(record)
    entry
  end

  # key => record, built once from the same groups the state is, so what a
  # question offers and what an answer resolves to cannot come apart.
  def records
    @records ||= GROUPS.each_with_object({}) do |group, map|
      offered(group.intent).each_with_index do |record, offset|
        map["#{group.prefix}_#{offset + 1}"] = record
      end
    end
  end

  # The inverse, for `#keys_for`. Records compare by identity the way
  # `Playthrough::Classifier#also_record` needs them to -- one person is one
  # entry however many names they answer to.
  def keys = @keys ||= records.invert

  def offered(action) = @offered[action.to_sym] ||= classifier.offered_for(action)
end
