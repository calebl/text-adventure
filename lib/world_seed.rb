# Seeded, playable worlds: the checked-in data files under db/seeds/worlds and
# the two halves of the tooling that keep them honest.
#
#   WorldSeed::Exporter  a generated Story -> a YAML file  (rake game:export)
#   WorldSeed::Loader    a YAML file -> database rows       (db/seeds.rb)
#
# Why this exists: generating a world costs minutes of live model calls and an
# API key, so a fresh clone had nothing to walk around in. A seeded world makes
# `bin/rails db:seed` produce something playable with no network at all.
#
# The files are AUTHORED ARTIFACTS. Export bootstraps one and rebuilds it after
# a schema change; from then on editing the YAML by hand is expected and
# supported. That is why the format is flat, ordered and commented rather than
# whatever was cheapest to emit -- see db/seeds/worlds/README.md.
module WorldSeed
  # Bumped when the file format changes in a way a loader cannot absorb. The
  # loader refuses a file it does not understand rather than half-loading it.
  #
  #   2  a world carries its own opening arrival: the required `opening_scene`
  #      key. A format 1 file has none, and a story without one opens on a room
  #      description standing in for an arrival nobody narrated.
  FORMAT = 2

  DIRECTORY = Rails.root.join("db/seeds/worlds")

  # The checked-in worlds, in a stable order so seeding is reproducible.
  def self.files
    Dir.glob(DIRECTORY.join("*.yml")).sort
  end

  # A filename for a story title: "The Drowned Ledger" -> "the-drowned-ledger".
  def self.slug(title)
    title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
  end

  # THE CHECKED-IN FILE FOR ONE STORY, matched on title the way
  # `WorldSeed::Loader` matches everything else, or nil for a story that is not
  # one of them -- which is every generated world and every engine-sweep copy.
  #
  # Nil on a malformed file too: a caller reading the file for corroborating
  # evidence must not be the thing that raises on a broken one, which is
  # `WorldSeed::Loader`'s job to complain about. `Story::Doctor` and
  # `Item::InventoryBackfill` both read it here rather than each opening the
  # path, so "is this one of ours" has one answer.
  def self.checked_in_document(title)
    path = DIRECTORY.join("#{slug(title)}.yml")
    File.exist?(path) ? parse(File.read(path)) : nil
  rescue StandardError
    nil
  end

  # Prose is stored as a literal block scalar (`|-`) rather than a folded or
  # quoted one: one paragraph is one physical line, so editing a sentence
  # produces a one-line diff instead of reflowing the whole field, and what you
  # type in an editor is exactly what gets stored. Psych falls back to a quoted
  # scalar on its own for the few strings a block scalar cannot hold.
  BLOCK_SCALAR_THRESHOLD = 60

  def self.dump(document)
    stream = Psych::Nodes::Stream.new
    doc = Psych::Nodes::Document.new
    doc.children << node(document)
    stream.children << doc
    stream.to_yaml
  end

  # Hand-edited files carry timestamps, so Date/Time are permitted; nothing
  # else is. Loading a seed file never instantiates an application object.
  def self.parse(yaml)
    YAML.safe_load(yaml, permitted_classes: [ Date, Time ], aliases: false)
  end

  def self.node(value)
    case value
    when Hash
      Psych::Nodes::Mapping.new.tap do |mapping|
        value.each do |key, child|
          mapping.children << node(key.to_s) << node(child)
        end
      end
    when Array
      # A short array of short scalars stays on one line -- `between` is a pair
      # of location names and reads as a pair.
      style = inline_array?(value) ? Psych::Nodes::Sequence::FLOW : Psych::Nodes::Sequence::BLOCK
      Psych::Nodes::Sequence.new(nil, nil, true, style).tap do |sequence|
        value.each { |child| sequence.children << node(child) }
      end
    when String
      scalar(value, style_for(value))
    when nil
      scalar("", Psych::Nodes::Scalar::ANY)
    else
      scalar(value.to_s, Psych::Nodes::Scalar::PLAIN)
    end
  end

  def self.style_for(value)
    return Psych::Nodes::Scalar::LITERAL if value.length > BLOCK_SCALAR_THRESHOLD || value.include?("\n")

    needs_quoting?(value) ? Psych::Nodes::Scalar::SINGLE_QUOTED : Psych::Nodes::Scalar::ANY
  end

  # Both implicit flags are set, which lets the emitter reach for quotes on its
  # own where the surrounding context demands them -- a name containing a comma
  # inside a flow sequence, say. Without that it emits a `!` tag instead.
  def self.scalar(value, style)
    Psych::Nodes::Scalar.new(value, nil, nil, true, true, style)
  end

  # Quote a short string only when leaving it bare would change what it means.
  # Asked of YAML itself rather than of a list of special cases: if the string
  # on its own does not parse back as that exact string, it needs quoting.
  # Compared by class as well as value, because ActiveSupport makes a Time
  # equal to a String that describes it -- an ISO timestamp is exactly the
  # case that has to come back quoted.
  def self.needs_quoting?(value)
    parsed = parse(value)
    !(parsed.is_a?(String) && parsed == value)
  rescue Psych::Exception
    true
  end

  def self.inline_array?(value)
    value.all? { |child| child.is_a?(String) && child.length <= BLOCK_SCALAR_THRESHOLD && !child.include?("\n") }
  end

  private_class_method :node, :inline_array?, :needs_quoting?, :style_for, :scalar
end
