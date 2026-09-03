# THE SAME HANDS PLAYING EVERY RUN.
#
# One file per world, one list of commands, played in order through
# `Playthrough::Turn#play` exactly as `NarrationJob` calls it. Fixed input is
# what makes two runs comparable at all: the only thing left free between a run
# and its repetition is what the models sampled, which is the noise
# `Eval::Noise` measures. A script that varied would fold the variation of the
# player into the variation of the game and neither could be read.
#
# WHAT A SCRIPT HAS TO DO, and why these are not eleven arbitrary commands. The
# three state checks that were dormant before this pipeline --
# `unreachable_transition`, `item_not_held`, `reached_for_nothing` -- can only
# fire on a run that MOVES, CARRIES and REACHES. So every script here walks into
# a room the world has never realized, walks back into one it has, puts
# something down and picks it up again, talks to somebody, and reaches for
# something that is not there. A script that only examined furniture would score
# a clean board on a broken game.
#
# `expect` is the branch the turn SHOULD take. It is recorded and reported, not
# enforced -- a `move` that the classifier resolved to nothing is a real finding
# (it writes a `Playthrough::Drift` row) and hiding it behind a retry would be
# measuring the harness rather than the game.
class Eval::Script
  DIRECTORY = Rails.root.join("lib/eval/scripts")

  Turn = Data.define(:id, :command, :expect, :beat, :note)

  attr_reader :story, :turns

  def initialize(story:, turns:)
    @story = story
    @turns = turns
  end

  def self.path_for(story) = DIRECTORY.join("#{WorldSeed.slug(story)}.yml")

  def self.for(story)
    file = path_for(story)
    raise ArgumentError, "no eval script for #{story.inspect} (expected #{file})" unless File.exist?(file)

    document = YAML.safe_load_file(file)
    raise ArgumentError, "#{file} is for #{document["story"].inspect}, not #{story.inspect}" if document["story"] != story

    new(story: story,
        turns: document.fetch("turns").map do |row|
          Turn.new(id: row.fetch("id"), command: row.fetch("command"),
                   expect: row["expect"], beat: row["beat"], note: row["note"])
        end)
  end

  def self.all = Eval::STORIES.map { |story| self.for(story) }

  def size = turns.size

  def first(count) = self.class.new(story: story, turns: turns.first(count))
end
