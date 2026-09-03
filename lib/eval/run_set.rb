# A SWEEP'S RUNS, SCORED TOGETHER.
#
# `Eval::RunSet.score(directory)` walks the manifests `script/eval_run.rb` left
# behind, opens each run's own database, and runs the SAME `Story::Audit` over
# it that `rake game:audit` runs over the captain's playthroughs. That is the
# whole point of keeping the databases: three of the sweep's checks read records
# rather than prose, and a corpus of loose passages cannot answer them.
#
# OFFLINE AND FREE. Scoring makes no model call and needs no API key, so it runs
# in the test suite and can be re-run on a set as often as a check changes.
# Generation is the only half that spends money and it lives in a different
# file for exactly that reason.
#
# WHAT IS DELIBERATELY EXCLUDED: the world's own opening arrival. It is
# hand-authored seed data, byte-identical in every run of that world, and
# counting it would add a constant to every denominator -- measuring the seed
# file rather than the game. `Story::Audit.new(story, scenes:)` is the seam.
class Eval::RunSet
  SCORES = "scores.json".freeze

  attr_reader :name, :path, :runs

  def initialize(name:, runs:, path: nil)
    @name = name
    @runs = runs
    @path = path
  end

  def self.load(directory)
    dir = Pathname.new(directory)
    file = dir.join(SCORES)
    raise ArgumentError, "#{file} does not exist -- score the set first (rake eval:score)" unless file.exist?

    document = JSON.parse(File.read(file))
    new(name: document["name"], path: dir, runs: document.fetch("runs").map { |row| Eval::RunScore.from_h(row) })
  rescue ArgumentError, KeyError => error
    # A SCORE FILE FROM AN OLDER SCORER. Scoring is free and the run databases
    # are still there, so the fix is to run it again rather than to migrate a
    # working file -- but the error has to say that rather than surfacing as a
    # missing keyword argument.
    raise ArgumentError, "#{file} was written by a different version of the scorer (#{error.message}). " \
                         "Re-score it: rake eval:score SET=#{dir.basename}"
  end

  # Scores every run in `directory` and writes `scores.json` beside them.
  def self.score(directory, io: $stdout)
    dir = Pathname.new(directory)
    manifests = Dir.glob(dir.join("runs", "*.json")).sort
    raise ArgumentError, "no runs in #{dir.join("runs")}" if manifests.empty?

    runs = manifests.map { |manifest| score_run(manifest, io: io) }
    set = new(name: dir.basename.to_s, path: dir, runs: runs)
    File.write(dir.join(SCORES), "#{JSON.pretty_generate(set.to_h)}\n")
    set
  end

  # ONE RUN, AGAINST ITS OWN DATABASE. The connection is swapped and put back:
  # the runs are separate SQLite files by design, and scoring them in one
  # process is what lets a sweep be scored by one command.
  def self.score_run(manifest_path, io: $stdout)
    manifest = JSON.parse(File.read(manifest_path))
    database = manifest_path.to_s.sub(/\.json\z/, ".sqlite3")
    raise ArgumentError, "#{database} is missing -- the run's records are what the state checks read" unless File.exist?(database)

    original = ActiveRecord::Base.connection_db_config
    begin
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database, timeout: 15_000, pool: 5)
      read(manifest, io: io)
    ensure
      ActiveRecord::Base.establish_connection(original)
    end
  end

  def self.read(manifest, io: $stdout)
    story = Story.find_by!(title: manifest.fetch("story"))
    scope = story.scenes.where(is_opening: false)
    audit = Story::Audit.new(story, scenes: scope)

    readings = Story::Scoreboard::CHECKS.keys.map do |code|
      Eval::RunScore::Reading.new(
        code: code,
        flagged: audit.flags.count { |flag| flag.code == code },
        judgeable: audit.judgeable_for(code),
        unjudged: audit.unjudged.count { |row| row.code == code },
        available: audit.available_checks.include?(code) && audit.judgeable_for(code).positive? &&
                   !Eval.unavailable_to_a_script?(code)
      )
    end

    typed_by_scene = audit.scenes.to_h { |scene| [ scene.id, scene.typed ] }
    # A CHECK THAT CANNOT ANSWER HERE RAISES NO FINDINGS EITHER, or the board
    # would print flags for a rate it declined to report. See
    # `Eval::UNAVAILABLE_TO_A_SCRIPT`.
    findings = audit.flags.reject { |flag| Eval.unavailable_to_a_script?(flag.code) }.map do |flag|
      Eval::RunScore::Finding.new(
        code: flag.code, story: story.title,
        turn: turn_index(manifest, flag.scene&.id),
        typed: flag.scene&.typed || typed_by_scene[flag.scene&.id],
        headline: flag.headline,
        claim: flag.evidence_line || flag.evidence[:claim],
        where: flag.evidence[:where] || flag.scene&.location&.name,
        evidence: flag.evidence.to_h { |key, value| [ key.to_s, value.to_s ] }
      )
    end

    richness = Eval::Richness.summarize(audit.scenes.map { |scene| Eval::Richness.for_scene(scene) })

    run = Eval::RunScore.new(
      story: story.title, held_out: Eval.held_out?(story.title), rep: manifest["rep"].to_i,
      model: manifest["pinned_model"],
      turns: manifest["turns"].to_a.size, scenes: audit.scanned,
      readings: readings, findings: findings, richness: richness,
      usage: Array(manifest["usage"]).map { |row| row.transform_keys(&:to_sym) },
      failures: manifest["turns"].to_a.filter_map { |turn| turn["failure"] && turn.slice("id", "failure") },
      drifts: manifest["turns"].to_a.flat_map { |turn| Array(turn["drifts"]).map { |drift| drift.merge("id" => turn["id"]) } },
      branches: manifest["turns"].to_a.to_h { |turn| [ turn["id"], { "expected" => turn["expect"], "took" => turn["branch"] } ] }
    )

    io&.puts format("  scored %-22s %2d turns  %s", run.label, run.scenes,
                    run.readings.select { |r| r.flagged.positive? }
                       .map { |r| "#{r.flagged} #{r.code}" }.join(", ").presence || "nothing flagged")
    run
  end

  # WHICH TURN OF THE SCRIPT A SCENE WAS, so a flag can be cited by turn id
  # rather than by a scene id out of a database that no longer exists.
  def self.turn_index(manifest, scene_id)
    return nil if scene_id.nil?

    manifest["turns"].to_a.find { |turn| turn["scene_id"] == scene_id }&.fetch("id", nil)
  end

  def stories = runs.map(&:story).uniq

  def tuning = runs.reject(&:held_out?)

  def held_out = runs.select(&:held_out?)

  def for_story(story) = runs.select { |run| run.story == story }

  def reps_of(story) = for_story(story).size

  def turns = runs.sum(&:scenes)

  def cost = Eval::Cost.actual(runs.flat_map(&:usage))

  # What the runs were pinned on. Plural because nothing stops a set holding
  # two, and a set that holds two is one a reader has to be told about.
  def models = runs.map(&:model).compact.uniq

  # THE SPREAD OF ONE CHECK OVER RUNS THAT SHOULD HAVE AGREED -- the noise
  # floor. Per story, because two worlds are two different measurements and
  # pooling them would report the difference between the worlds as noise.
  def spread(code, story)
    Eval::Noise.spread(code, for_story(story).select { |run| run.available?(code) }.map { |run| run.rate(code) })
  end

  def richness_spread(story)
    Eval::Noise.spread(:richness, for_story(story).map { |run| run.richness.commitments })
  end

  # Every run's rate for a check, over the stories asked for -- what
  # `Eval::Comparison` hands to `Eval::Noise`.
  def rates(code, stories: nil)
    scope = stories ? runs.select { |run| Array(stories).include?(run.story) } : runs
    scope.select { |run| run.available?(code) }.map { |run| run.rate(code) }
  end

  # THE COUNTER-METRIC'S OWN PER-RUN FIGURE, handed to the same test the checks
  # get. Mean commitments a turn -- see `Eval::Richness` for why not the density.
  def richness_rates(stories: nil)
    scope = stories ? runs.select { |run| Array(stories).include?(run.story) } : runs
    scope.map { |run| run.richness.commitments }
  end

  def to_h = { name:, recorded_at: Time.current.utc.iso8601, runs: runs.map(&:to_h) }
end
