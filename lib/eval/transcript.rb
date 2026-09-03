# A RUN, AS SOMETHING A PERSON READS.
#
# The board prints what a check CAUGHT, which is the right default -- the whole
# point of the loop is that nobody reads a clean turn again. This prints the
# opposite: every turn of one run, in order, with what was typed, the passage
# the player would have read, and a mark against any turn a check flagged.
#
# WHY IT EXISTS. The captain, on the held-out world scoring zero flags across 88
# turns: *"the clean board is confusing. How can I read it to verify?"* A clean
# board is only worth anything if the turns behind it can be read, and a run
# lives in a SQLite file under `tmp/` that nothing else opens. This is the
# reading.
#
# `rake 'eval:read[The Salt Assizes,1]'` -- offline, no model call, no key.
class Eval::Transcript
  Turn = Data.define(:index, :typed, :room, :prose, :codes, :branch, :resolution) do
    # Defaulted, because `resolution` is what a run recorded about itself and a
    # set generated before `Scene#resolved_action` existed recorded nothing.
    def initialize(resolution: nil, **rest) = super

    def flagged? = codes.any?
  end

  attr_reader :set, :story, :rep, :turns, :io

  def initialize(set:, story:, rep:, turns:, io: $stdout)
    @set = set
    @story = story
    @rep = rep
    @turns = turns
    @io = io
  end

  # Reads one run out of its own database, the same way `Eval::RunSet` scores
  # it, and pairs each turn with whatever the sweep flagged on it.
  def self.read(directory, story:, rep: 1, io: $stdout)
    scored = Eval::RunSet.load(directory)
    run = scored.runs.find { |candidate| candidate.story == story && candidate.rep == rep }
    raise ArgumentError, "#{directory} has no run of #{story.inspect} at rep #{rep}. " \
                         "It has: #{scored.runs.map(&:label).join(", ")}" if run.nil?

    manifest = JSON.parse(File.read(Pathname.new(directory).join("runs", "#{WorldSeed.slug(story)}-r#{rep}.json")))
    codes = run.findings.group_by(&:turn).transform_values { |found| found.map(&:code).uniq }

    turns = manifest.fetch("turns").map do |turn|
      Turn.new(index: turn["id"], typed: turn["command"], room: turn["location_after"],
               prose: prose_for(directory, story, rep, turn["scene_id"]),
               resolution: resolution_for(directory, story, rep, turn),
               codes: codes.fetch(turn["id"], []), branch: turn["branch"])
    end

    new(set: scored.name, story: story, rep: rep, turns: turns, io: io)
  end

  # The passage as it was stored, read out of the run's own database. Opened
  # once per turn rather than held, because a transcript is printed once and
  # the alternative is keeping a connection open across the whole render.
  def self.prose_for(directory, story, rep, scene_id)
    return nil if scene_id.nil?

    scenes_in(directory, story, rep).dig(scene_id, :prose)
  end

  # WHAT THE TURN RESOLVED TO, in the app's own words: `take -> Assize
  # tide-slate`. The captain reads a run here, and reconstructing what a line
  # was read as -- from the branch, the room it ended in and the prose -- is
  # the work this whole record exists to stop him doing.
  #
  # The run's own `Scene#resolution` first, because that is the record. The
  # manifest's `intents` is the fallback and covers every run played before the
  # columns existed: it is the same `Intent`, written down by the harness at the
  # time, so an old transcript still reads.
  def self.resolution_for(directory, story, rep, turn)
    stored = turn["scene_id"] && scenes_in(directory, story, rep).dig(turn["scene_id"], :resolution)
    return stored if stored.present?

    Array(turn["intents"]).filter_map do |intent|
      "#{intent["action"]} -> #{intent["subject"] || "nothing"}"
    end.join(", ").presence
  end

  # Every scene of one run, read once: the passage and what the turn did.
  # `acted_on` is followed to a name INSIDE the block, because the connection is
  # put back the way it was found on the way out.
  #
  # `Scene#resolution` answers nil rather than raising on a run database whose
  # `scenes` table has no such column -- every set swept before that migration.
  # Those transcripts still read: the manifest carries the same `Intent`, see
  # `.resolution_for`.
  def self.scenes_in(directory, story, rep)
    @scenes ||= {}
    key = [ directory.to_s, story, rep ]
    @scenes[key] ||= begin
      database = Pathname.new(directory).join("runs", "#{WorldSeed.slug(story)}-r#{rep}.sqlite3")
      original = ActiveRecord::Base.connection_db_config
      begin
        ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database.to_s, timeout: 15_000)
        Scene.where(story: Story.find_by!(title: story)).to_h do |scene|
          [ scene.id, { prose: scene.description, resolution: scene.resolution } ]
        end
      ensure
        ActiveRecord::Base.establish_connection(original)
      end
    end
  end

  def flagged = turns.select(&:flagged?)

  def print
    io.puts "#{story} -- run #{rep} of set #{set.inspect}"
    io.puts "  #{turns.size} turns, #{flagged.size} of them flagged by a check."
    io.puts "  A turn with no mark is a turn every check passed. THOSE are the ones to read"
    io.puts "  when a board looks too clean: is the prose really consistent with the records?"
    io.puts

    turns.each do |turn|
      mark = turn.flagged? ? "FLAGGED #{turn.codes.join(", ")}" : "clean"
      io.puts "-- #{turn.index}  [#{turn.branch}] in #{turn.room} -- #{mark}"
      io.puts "   > #{turn.typed}"
      io.puts "   resolved: #{turn.resolution}" if turn.resolution.present?
      io.puts
      io.puts wrap(turn.prose.presence || "(no passage -- the turn failed)")
      io.puts
    end

    self
  end

  private

  # Hard-wrapped at a width a terminal has, because the passages are one long
  # line each in the database and reading one unwrapped is not reading it.
  def wrap(text, width: 88)
    text.to_s.split("\n").flat_map do |paragraph|
      paragraph.scan(/\S.{0,#{width - 4}}(?:\s|\z)/).map { |line| "   #{line.strip}" }.presence || [ "" ]
    end.join("\n")
  end
end
