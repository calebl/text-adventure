namespace :game do
  desc "Generate a new universe and story. Usage: rake 'game:new[a heist on a generation ship]'"
  task :new, [ :premise ] => :environment do |t, args|
    premise = args[:premise]

    puts "Premise: #{premise.presence || "chosen by the model"}"
    puts "Model:   #{BaseAgent.default_model_options.first&.fetch(:model, nil) || "NONE -- set OPENROUTER_API_KEY"}"
    puts

    # Generate both before saving anything. Persisting the universe first
    # leaves a dangling universe behind whenever story generation fails.
    universe = Helpers.timed("Generating universe") { Universe::Generator.new(premise: premise).generate }
    story = Helpers.timed("Generating story") { Story::Generator.new(universe, premise: premise).generate }

    Helpers.persist!(universe, story)

    # The opening location is generated after the story is saved because
    # realizing it writes stub neighbours and connection rows, which need ids.
    # A failure here leaves a story you can still open a location in later.
    location = Helpers.timed("Generating opening location") { Location::Generator.opening(story) }

    # The opening arrival, narrated ONCE, here, where nobody is waiting on it.
    # Without this a generated world and a seeded one are different shapes: a
    # seeded world carries its own opening arrival and a generated one would
    # not, so the first thing a player read would depend on how the world was
    # made. Costs one Scene::Generator call (~1,302 in / ~200 out) and buys the
    # player a first screen with no model call behind it at all.
    #
    # The cast is empty at this point -- `game:new` makes no characters, and
    # `Character::Generator` never sets `is_protagonist` -- so the arrival is
    # written with nobody in the room. Add a cast in the exported seed file;
    # that is what makes the talk branch reachable from turn one.
    scene = Helpers.timed("Narrating the opening arrival") { Scene::Generator.opening(story) }

    puts
    puts "=" * 72
    puts story.title
    puts "#{story.genre} -- universe ##{universe.id}, story ##{story.id}"
    puts "=" * 72
    puts
    puts story.preface
    puts
    puts scene.description
    puts
    puts "Ways out:"
    location.exits.each do |exit|
      connection = LocationConnection.find_by(location: location, connected_location: exit)
      puts "  #{exit.name} -- #{exit.teaser} (#{connection&.distance}, #{connection&.time_to_travel} #{connection&.travel_method})"
    end
    puts
    puts "Add a character with: rails runner \"Story.find(#{story.id}).create_character\""
    puts "Export it to a hand-editable seed file with: rake 'game:export[#{story.id}]'"
  end

  desc "Export a generated world to a checked-in seed file. Usage: rake 'game:export[3]'"
  task :export, [ :story_id, :path ] => :environment do |t, args|
    story = Story.find(args[:story_id])
    exporter = WorldSeed::Exporter.new(story)
    path = exporter.write!(path: args[:path])

    inside_app = path.to_s.start_with?(Rails.root.to_s)
    puts "Exported #{story.title.inspect} to #{inside_app ? path.relative_path_from(Rails.root) : path}"

    if exporter.warnings.any?
      puts
      puts "Warnings:"
      exporter.warnings.each { |warning| puts "  - #{warning}" }
    end

    puts
    puts "The file is an authored artifact from here on -- edit it by hand, then"
    puts "check it loads with: bin/rails db:seed"
  end

  desc "List generated stories"
  task list: :environment do
    stories = Story.includes(:universe).order(:created_at)

    if stories.empty?
      puts "No stories yet. Generate one with: rake 'game:new[your premise]'"
      next
    end

    stories.each do |story|
      puts "##{story.id}  #{story.title} (#{story.genre})"
      puts "     universe ##{story.universe_id}  characters: #{story.characters.count}  locations: #{story.locations.count} (#{story.locations.realized.count} realized)  scenes: #{story.scenes.count}"
    end
  end

  desc "Report on the health of every story, or one. Usage: rake game:doctor or rake 'game:doctor[3]'"
  task :doctor, [ :story_id ] => :environment do |t, args|
    doctors = args[:story_id] ? [ Story::Doctor.new(Helpers.story!(args[:story_id])) ] : Story::Doctor.all

    if doctors.empty?
      puts "No stories yet. Generate one with: rake 'game:new[your premise]'"
      next
    end

    doctors.each { |doctor| Helpers.print_diagnosis(doctor) }

    playable, unplayable = doctors.partition(&:playable?)
    healthy = doctors.count(&:healthy?)
    puts "=" * 72
    puts "#{doctors.size} stor#{doctors.one? ? "y" : "ies"}: #{healthy} healthy, " \
         "#{playable.size - healthy} playable with warnings, #{unplayable.size} unplayable"
  end

  desc "Fix what can be fixed about a story. Usage: rake 'game:repair[3]', GENERATE=1 to allow model calls"
  task :repair, [ :story_id ] => :environment do |t, args|
    story = Helpers.story!(args[:story_id])
    generate = ENV["GENERATE"].present?
    repair = Story::Repair.new(story, generate: generate)

    puts "#{story.title} (##{story.id})"
    puts

    if repair.plan.empty? && repair.deferred.empty? && repair.manual.empty?
      puts "Nothing to repair -- `rake 'game:doctor[#{story.id}]'` finds nothing wrong with it."
      next
    end

    if repair.plan.any?
      calls = repair.model_calls
      if calls.positive?
        puts "About to make #{calls} model call#{"s" unless calls == 1}. That spends tokens and needs OPENROUTER_API_KEY"
        puts "or a local ollama -- see BaseAgent."
        puts
      end

      puts "Repairing:"
      repair.apply!.each do |result|
        mark = result.repaired? ? "  ok " : "  FAILED "
        puts "#{mark}#{result.message}"
      end
      puts
    end

    if repair.deferred.any?
      puts "Not attempted -- these need a model call, so they are opt-in:"
      repair.deferred.each { |finding| puts "  - #{finding.message}" }
      puts "  Run again with: GENERATE=1 rake 'game:repair[#{story.id}]'"
      puts
    end

    if repair.manual.any?
      puts "Cannot be repaired -- there is no honest answer to backfill, and this never invents one:"
      repair.manual.each { |finding| puts "  - #{finding.message}" }
      puts "  Fix by hand, or delete the story: rake 'game:delete[#{story.id}]'"
      puts
    end

    puts "Now: #{Story::Doctor.new(story.reload).headline}"
  end

  desc "Audit stored narration against the records. Usage: rake game:audit or rake 'game:audit[3]', VERBOSE=1 for unjudged checks"
  task :audit, [ :story_id ] => :environment do |t, args|
    audits = args[:story_id] ? [ Story::Audit.new(Helpers.story!(args[:story_id])) ] : Story::Audit.all

    if audits.empty?
      puts "No stories yet. Generate one with: rake 'game:new[your premise]'"
      next
    end

    puts "Reading stored scenes against the records. No model call, no API key, no network."
    puts

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    audits.each { |audit| Helpers.print_audit(audit, verbose: ENV["VERBOSE"].present?) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    Helpers.print_audit_summary(audits, elapsed)
  end

  desc "Label old turns with what they did, from the classifier answers still on disk. Usage: rake game:backfill_transitions, DRY_RUN=1 to see it first"
  task :backfill_transitions, [ :story_id ] => :environment do |t, args|
    scope = args[:story_id] ? Story.where(id: Helpers.story!(args[:story_id]).id) : Story.all
    dry = ENV["DRY_RUN"].present?

    puts "WHAT EACH OLD TURN DID, recovered from the classifier's own stored answer."
    puts "`scenes.resolved_action` and `scenes.acted_on` are written by the loop from now on"
    puts "(Playthrough::Turn#play); this labels what was played before they existed, and it can"
    puts "only label a turn whose classifier exchange is still on disk. Offline, no model call."
    puts "DRY RUN: nothing is written." if dry
    puts

    total = Hash.new(0)
    scope.order(:created_at, :id).each do |story|
      counts = Scene::TransitionBackfill.new(story).run(dry_run: dry)
      next if counts.values.sum.zero?

      puts format("  %-40s labelled %3d, resolved to nothing %3d, unrecoverable %3d",
                  story.title.truncate(40), counts[:labelled], counts[:drifted], counts[:unrecoverable])
      counts.each { |key, count| total[key] += count }
    end

    puts
    if total.values.sum.zero?
      puts "Nothing to do: every turn already carries what it did."
    else
      puts "#{total[:labelled]} turn(s) labelled with an action and the record it acted on."
      puts "#{total[:drifted]} turn(s) labelled with an action and no record -- the classifier resolved to nothing,"
      puts "  which is the drift case and a fact about the turn rather than a gap."
      puts "#{total[:unrecoverable]} turn(s) left blank: the answer named something these records no longer have,"
      puts "  or the exchange has been pruned (Chat::KEEP_TURNS). A blank column is honest; a guess is not."
    end
  end

  desc "Split today's items into the world's own rows and each playthrough's copies. Usage: rake game:backfill_items, DRY_RUN=1 to see it first"
  task :backfill_items, [ :story_id ] => :environment do |t, args|
    scope = args[:story_id] ? Story.where(id: Helpers.story!(args[:story_id]).id) : Story.all
    dry = ENV["DRY_RUN"].present?

    puts "THE WORLD IS THE TEMPLATE AND THE PLAYTHROUGH OWNS THE INSTANCES."
    puts "Before the captain's ruling of 2026-09-04 there was one layer and every game shared"
    puts "it: a party that picked the ward stamp up took it out of the room for every other"
    puts "play of that world. This puts the world's own rows back where the turn log says they"
    puts "were taken from, hands each row a take records to the player who took it, and gives"
    puts "every existing game its own copy of what is lying in the rooms it has walked through."
    puts "It REFUSES TO GUESS, and it is idempotent: a second run reports nothing to do."
    puts "Offline, no model call."
    puts "DRY RUN: nothing is written." if dry
    puts

    total = Hash.new(0)
    copied = 0
    scope.order(:created_at, :id).each do |story|
      result = Item::LayerBackfill.new(story).run(dry_run: dry)
      answers = result.answers
      snapshots = result.snapshots.reject { |snapshot| snapshot.copies.empty? }
      next if answers.empty? && snapshots.empty?

      puts format("  %-40s the world's own %3d, attributed %3d, left alone %3d, unaccounted %3d",
                  story.title.truncate(40),
                  answers.count(&:template?), answers.count(&:attributed?),
                  answers.count(&:ambiguous?), answers.count(&:unrecoverable?))

      answers.each do |answer|
        total[answer.outcome] += 1
        case answer.outcome
        when :attributed
          where = answer.location ? ", and the world's own row goes back to #{answer.location.name}" : ""
          puts "      #{answer.item.name} -> playthrough ##{answer.playthrough.id}'s own copy#{where}"
        when :ambiguous
          puts "      #{answer.item.name} -- LEFT ALONE: playthrough(s) #{answer.playthroughs.map { |p| "##{p.id}" }.join(" and ")} " \
               "record taking it at the same moment, and an item was in one place"
        when :unrecoverable
          puts "      #{answer.item.name} -- LEFT WHERE IT IS: nothing on record says what it is a copy of. " \
               "It stays in that player's game and `rake game:doctor` reports it"
        end
      end

      snapshots.each do |snapshot|
        copied += snapshot.copies.size
        puts "      playthrough ##{snapshot.playthrough.id} takes its own copy of #{snapshot.copies.size} thing(s) " \
             "across #{snapshot.rooms.size} room(s) it has been in: #{snapshot.copies.map(&:name).join(", ")}"
      end
    end

    puts
    if total.values.sum.zero? && copied.zero?
      puts "Nothing to do: this database has no items in it."
    elsif total[:attributed].zero? && total[:ambiguous].zero? && total[:unrecoverable].zero? && copied.zero?
      puts "Nothing to do: every row is already in the layer it belongs in and every game holds its copies."
    else
      puts "#{total[:template]} row(s) are the world's own and were left exactly where they stand."
      puts "#{total[:attributed]} row(s) became the copy of the player whose turn log took them, with the world's"
      puts "  own row put back in the room the take happened in."
      puts "#{copied} copy(ies) handed to existing playthroughs for the rooms they have walked through."
      puts "#{total[:ambiguous]} left alone: two playthroughs took the same thing at the same moment, and choosing"
      puts "  between them would be inventing which player had it."
      puts "#{total[:unrecoverable]} left where they are: nothing says what they are a copy of, and taking a thing"
      puts "  out of somebody's hands to tidy the records is the one destructive thing this could do."
      puts "`rake game:doctor` shows the result."
    end
  end


  desc "Place characters who have no whereabouts, from the arrival casts still on disk. Usage: rake game:backfill_whereabouts, DRY_RUN=1 to see it first"
  task :backfill_whereabouts, [ :story_id ] => :environment do |t, args|
    scope = args[:story_id] ? Story.where(id: Helpers.story!(args[:story_id]).id) : Story.all
    dry = ENV["DRY_RUN"].present?

    puts "WHERE SOMEBODY WAS, recovered from the only record that ever held it."
    puts "`characters.location_id` is the closed set `talk` resolves against and is written from"
    puts "now on -- by the seed file, by Character::Registry, by Character#move_to!. This places"
    puts "the people a world had before the column existed, out of the cast of the last arrival"
    puts "Scene that recorded them, and it REFUSES TO GUESS. Offline, no model call."
    puts "DRY RUN: nothing is written." if dry
    puts

    total = Hash.new(0)
    scope.order(:created_at, :id).each do |story|
      answers = Character::WhereaboutsBackfill.new(story).run(dry_run: dry)
      next if answers.empty?

      puts format("  %-40s placed %3d, ambiguous %3d, never recorded %3d",
                  story.title.truncate(40),
                  answers.count(&:placed?), answers.count(&:ambiguous?),
                  answers.count { |answer| answer.outcome == :unrecoverable })

      answers.each do |answer|
        total[answer.outcome] += 1
        case answer.outcome
        when :placed then puts "      #{answer.character.fullname} -> #{answer.location.name}"
        when :ambiguous then puts "      #{answer.character.fullname} -- left nowhere: recorded in #{answer.rooms.join(" and ")} with no order to choose from"
        end
      end
    end

    puts
    if total.values.sum.zero?
      puts "Nothing to do: everybody who can carry a whereabouts has one."
    else
      puts "#{total[:placed]} character(s) placed where the last arrival that recorded them says they were."
      puts "#{total[:ambiguous]} left nowhere: two rooms recorded them at the same moment, or the scenes that"
      puts "  recorded them carry no story time. A person cannot be in two rooms and this will not pick one."
      puts "#{total[:unrecoverable]} left nowhere: no scene ever recorded them, so there is nothing to recover."
      puts
      puts "The protagonist and any companions are deliberately skipped: the party is wherever the"
      puts "playthrough is (`playthroughs.current_location_id`), and two players stand in two rooms."
      puts "`rake game:doctor` reports whoever is still nowhere."
    end
  end

  desc "Roll a body for everybody who has no stat block. Usage: rake game:backfill_stat_blocks, DRY_RUN=1 to see it first"
  task :backfill_stat_blocks, [ :story_id ] => :environment do |t, args|
    scope = args[:story_id] ? Story.where(id: Helpers.story!(args[:story_id]).id) : Story.all
    dry = ENV["DRY_RUN"].present?

    puts "A BODY FOR EVERYBODY WHO WAS WRITTEN BEFORE THERE WERE BODIES."
    puts "`characters.level` and `characters.hit_die` are written from now on -- by a seed file, by"
    puts "Character::Registry and by Character::Generator. This rolls one for every character older"
    puts "than the columns, because the engine is the only author those numbers ever had (the"
    puts "captain's ruling of 2026-09-04). Deterministic, so this dry run's numbers are the ones a"
    puts "real run writes. Offline, no model call."
    puts "DRY RUN: nothing is written." if dry
    puts

    rolled = 0
    scope.order(:created_at, :id).each do |story|
      answers = Character::StatBackfill.new(story).run(dry_run: dry)
      next if answers.empty?

      rolled += answers.size
      puts format("  %-40s rolled %3d", story.title.truncate(40), answers.size)
      answers.each { |answer| puts "      #{answer}" }
    end

    puts
    if rolled.zero?
      puts "Nothing to do: everybody in the database already has a body."
    else
      puts "#{rolled} stat block(s) rolled. `Character#max_hp` follows from them, and every"
      puts "playthrough takes its own copy of a condition at first contact (Playthrough::Vitals)."
      puts "A seeded world's `characters[].stats` re-asserts itself over these on the next"
      puts "`bin/rails db:seed`, which is the file being the decision it always is."
    end
  end

  desc "Score the game against the errors that can be checked. Usage: rake game:score, SAVE=1 to re-baseline, CORPUS=database|corpus|transitions"
  task :score, [ :story_id ] => :environment do |t, args|
    boards =
      if args[:story_id]
        [ Story::Scoreboard.database(Story.where(id: Helpers.story!(args[:story_id]).id)) ]
      else
        Story::Scoreboard.all
      end
    boards.select! { |board| board.name == ENV["CORPUS"] } if ENV["CORPUS"].present?

    if boards.empty?
      puts "No corpus to score. CORPUS must be one of: database, corpus, transitions."
      next
    end

    puts "Scoring stored turns against the records. No model call, no API key, no network."
    puts

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    boards.each { |board| Helpers.print_scoreboard(board) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    Helpers.print_score_footer(boards, elapsed)
  end

  desc "Delete a story and everything that belongs only to it. Usage: rake 'game:delete[3]' (dry run unless confirmed)"
  task :delete, [ :story_id ] => :environment do |t, args|
    story = Helpers.story!(args[:story_id])
    deletion = Story::Deletion.new(story)

    puts "#{story.title} (##{story.id}) -- #{story.genre}"
    puts
    puts "This would remove:"
    deletion.manifest.each { |label, count| puts format("  %-16s %d", label, count) }
    puts "  #{deletion.universe_disposition}"
    puts

    if ENV["DRY_RUN"].present?
      puts "DRY RUN: nothing was deleted."
      next
    end

    confirm = ENV["CONFIRM"]
    if confirm.nil? && $stdin.tty?
      print "Type the story's title to delete it, or anything else to cancel: "
      confirm = $stdin.gets.to_s
    end

    if confirm.nil?
      abort "Not deleted. Re-run with CONFIRM=#{story.title.inspect} to delete it, or DRY_RUN=1 to see this again."
    end

    begin
      removed = deletion.destroy!(confirm: confirm)
    rescue Story::Deletion::NotConfirmed => e
      abort "Not deleted: #{e.message}"
    end

    puts
    puts "Deleted #{story.title.inspect} and #{removed.values.sum} record(s) that belonged to it."
  end

  desc "Walk a world with the narration switched off. Usage: rake 'game:mechanics[3]', NO_MODEL=1 for the offline grammar"
  task :mechanics, [ :story ] => :environment do |t, args|
    playthrough = Helpers.mechanics_playthrough!(args[:story])
    model = ENV["NO_MODEL"].blank?
    mechanics = Playthrough::Mechanics.new(playthrough, model: model)
    story = playthrough.story

    puts "#{story.title} (story ##{story.id}) -- MECHANICS ONLY: the narration is off."
    if model
      puts "The classifier still reads what you type (one model call a command, so this needs"
      puts "a key), and the world still generates itself as you walk into it. What you do not"
      puts "get is prose: no narrator, no character, just the records and what changed."
      puts "NO_MODEL=1 for the offline grammar instead."
    else
      puts "NO MODEL AT ALL: a fixed grammar instead of the classifier, no generation, no API"
      puts "key, no network. A room nobody has written stays unwritten. `help` for the grammar."
    end
    puts "Playing as #{playthrough.character&.fullname || "nobody"}, playthrough ##{playthrough.id}."
    puts "`help` for what this understands, `quit` to stop."
    puts
    puts mechanics.read
    puts

    # Echoed back when stdin is a file or a pipe, so a scripted walk reads as a
    # transcript rather than as a wall of answers to invisible questions.
    interactive = $stdin.tty?

    loop do
      print "> " if interactive
      line = $stdin.gets
      break if line.nil?

      line = line.chomp
      puts "> #{line}" unless interactive
      break if Helpers::MECHANICS_QUIT.include?(line.strip.downcase)

      # A FAILED MODEL CALL IS NOT A BAD COMMAND, and the console says which it
      # was rather than dying on it: the classifier is the only thing here that
      # can fail that way, and a session that ends on a rate limit loses the walk
      # that was being set up.
      begin
        puts mechanics.run(line)
      rescue StandardError => e
        puts "  FAILED:     the classifier call did not land -- #{e.class}: #{e.message}"
        puts "              Nothing changed. Try again, or run with NO_MODEL=1 for the offline grammar."
        puts mechanics.state
      end
      puts
    end

    playthrough.reload
    puts
    puts "Left #{playthrough.character&.fullname || "the playthrough"} in " \
         "#{playthrough.current_location&.name || "nowhere"}, carrying " \
         "#{playthrough.carried.pluck(:name).presence&.join(", ") || "nothing"}."
    puts "Pick it up again with: PLAYTHROUGH=#{playthrough.id} rake 'game:mechanics[#{story.id}]'"
  end

  desc "Walk every stored script through the engine offline and assert the records. Usage: rake game:sweep, SCRIPT=<name> for one"
  task :sweep, [ :script ] => :environment do |t, args|
    wanted = args[:script].presence || ENV["SCRIPT"].presence
    scripts = EngineSweep.scripts
    scripts = scripts.select { |script| script.name == wanted || script.story == wanted } if wanted

    if scripts.empty?
      abort "No sweep script #{wanted.inspect}. There is: #{EngineSweep.scripts.map(&:name).join(", ")}" if wanted

      abort "There are no sweep scripts in #{EngineSweep::DIRECTORY}."
    end

    puts "THE ENGINE SWEEP: #{scripts.size} script(s), no model, no network, no key."
    puts "Each one loads its own copy of a seeded world and rolls it back. Nothing here is kept."
    puts

    results = EngineSweep.run(scripts)
    results.each { |result| puts result.line }

    failed = results.reject(&:passed?)
    puts

    if failed.empty?
      puts "PASSED: #{results.sum(&:steps)} typed line(s) over #{results.size} script(s)."
      next
    end

    failed.each do |result|
      puts result.report
      puts
    end

    # Flushed before the abort, which writes to stderr: a CI log that
    # interleaves the two puts the verdict above the findings it is about.
    $stdout.flush

    abort "FAILED: #{failed.sum { |result| result.failures.size }} expectation(s) unmet " \
          "in #{failed.size} of #{results.size} script(s)."
  end

  # Namespaced under a module rather than defined at rake top level, where
  # they would land on Object -- `save!` in particular collides badly there.
  module Helpers
    # ----------------------------------------------------------------------
    # THE MECHANICS CONSOLE. `rake game:mechanics`.
    # ----------------------------------------------------------------------

    MECHANICS_QUIT = %w[quit q exit bye].freeze

    # A story by id or by title, because the console is typed by hand and a
    # title is what a person remembers.
    def self.story_by!(reference)
      return story!(reference) if reference.to_s.match?(/\A\d+\z/)

      story = Story.find_by("LOWER(title) = ?", reference.to_s.strip.downcase) if reference.present?
      return story if story

      known = Story.order(:id).pluck(:id, :title).map { |id, title| "##{id} #{title}" }
      abort "Name a story: rake 'game:mechanics[<id or title>]'." +
            (known.any? ? " There is: #{known.join(", ")}" : " There are no stories at all -- try `bin/rails db:seed`.")
    end

    # The playthrough the console drives.
    #
    # A FRESH ONE by default, and deliberately: a mechanics session moves the
    # player around and takes things off the floor, and doing that to whichever
    # playthrough happened to be last would edit somebody's game. `PLAYTHROUGH=`
    # attaches to an existing one -- by id or by the token in its URL -- for
    # when inspecting a real game is the point.
    #
    # Where items ARE in the WORLD is world state and is shared either way:
    # something left in the closet in one session is still in the closet in the
    # next one, and in the browser. That is the thing being tested, so it is not
    # isolated. What a PARTY is carrying is not shared -- it is on
    # `items.playthrough_id` -- so a fresh playthrough here opens with the
    # story's starting inventory and nothing another game picked up.
    def self.mechanics_playthrough!(reference)
      if ENV["PLAYTHROUGH"].present?
        named = ENV["PLAYTHROUGH"]
        playthrough = Playthrough.find_by(id: named) || Playthrough.find_by(token: named)
        abort "No playthrough #{named.inspect}. Drop PLAYTHROUGH= to start a fresh one." if playthrough.nil?
        return playthrough
      end

      story = story_by!(reference)
      opening = story.locations.realized.order(:id).first
      abort "#{story.title.inspect} has no realized location to stand in -- see `rake 'game:doctor[#{story.id}]'`." if opening.nil?

      Playthrough.create!(
        story: story,
        character: story.protagonist,
        current_location: opening,
        # The world's own opening arrival when it has one, so a playthrough
        # started here and one started in the browser read the same turn log.
        # No Scene is written by the console itself.
        current_scene: story.opening_scene
      )
    end

    # A story by id, or an abort that says what ids there are. `Story.find`
    # raises a RecordNotFound whose backtrace buries the one useful fact.
    def self.story!(id)
      Story.find(id)
    rescue ActiveRecord::RecordNotFound
      known = Story.order(:id).pluck(:id, :title).map { |story_id, title| "##{story_id} #{title}" }
      abort "No story ##{id}." + (known.any? ? " There is: #{known.join(", ")}" : " There are no stories at all.")
    end

    # What the tool can do about a finding, in three characters of column.
    REMEDY_LABELS = {
      safe: "repairable",
      generate: "model call",
      manual: "by hand"
    }.freeze

    # One story's diagnosis, in the shape `rake game:list` already reads in.
    def self.print_diagnosis(doctor)
      story = doctor.story
      puts "##{story.id}  #{story.title} (#{story.genre})"
      puts "     #{doctor.healthy? ? "HEALTHY" : "#{doctor.playable? ? "PLAYABLE" : "UNPLAYABLE"} -- #{doctor.findings.size} problem(s)"}"

      doctor.findings.each do |finding|
        puts "     #{finding.fatal? ? "X" : "!"} [#{REMEDY_LABELS.fetch(finding.remedy)}] #{finding.message}"
      end

      if doctor.findings.any? { |finding| finding.remedy == :safe }
        puts "     -> rake 'game:repair[#{story.id}]'"
      end
      if doctor.findings.any? { |finding| finding.remedy == :generate }
        puts "     -> GENERATE=1 rake 'game:repair[#{story.id}]'  (costs model calls)"
      end
      if !doctor.playable? && doctor.fatal.all? { |finding| finding.remedy == :manual }
        puts "     -> nothing can repair this honestly: rake 'game:delete[#{story.id}]'"
      end
      puts
    end

    # One story's audit. Contradictions first -- those are the ones the records
    # prove -- then drift, which is evidence and reported as evidence.
    def self.print_audit(audit, verbose: false)
      story = audit.story
      puts "##{story.id}  #{story.title} (#{story.genre})"
      puts "     #{audit.headline}"

      audit.contradictions.each { |flag| print_flag("X", flag) }
      audit.drifts.each { |flag| print_flag("~", flag) }
      audit.limits.each { |flag| print_flag("-", flag) }

      if audit.unjudged.any?
        puts "     #{audit.unjudged.size} check(s) not judged -- the records cannot answer them honestly#{" (VERBOSE=1 to list)" unless verbose}"
        audit.unjudged.each { |skipped| puts "       - [#{skipped.code}] scene ##{skipped.scene&.id}: #{skipped.reason}" } if verbose
      end

      puts
    end

    # A flag with everything needed to judge it, because a flag nobody can
    # judge is a flag everybody learns to ignore.
    def self.print_flag(mark, flag)
      puts "     #{mark} [#{flag.code}] scene ##{flag.scene&.id}#{" (#{flag.scene.location&.name})" if flag.scene&.location}"
      puts "       #{flag.headline}"
      flag.evidence.each { |key, value| puts "         #{key}: #{value}" if value.present? }
    end

    # ----------------------------------------------------------------------
    # THE SCOREBOARD. `rake game:score`.
    #
    # The shape of this output is the answer to the second half of what was
    # asked for -- *"having me review everything manually is too slow and I
    # start losing focus from reading variations on the same thing too many
    # times"* -- so it is organised so that nothing clean is ever printed. Every
    # line is either a number or a turn a check caught, and every caught turn
    # carries what was typed and the sentence that convicted it.
    # ----------------------------------------------------------------------

    # How a flag is marked, worst class first. Same three characters the audit
    # uses, plus one each for a limit of the loop and for pacing, neither of
    # which is a defect and neither of which must read like one.
    SCORE_MARKS = { contradiction?: "X", defect?: "X", drift?: "~", limit?: "-", pacing?: "-" }.freeze

    def self.print_scoreboard(board)
      puts "=" * 78
      puts "CORPUS: #{board.name}"
      puts "  #{board.note}" if board.note
      puts "  #{board.scanned} turn#{"s" unless board.scanned == 1} across #{board.audits.size} " \
           "#{board.name == "database" ? "stor#{board.audits.one? ? "y" : "ies"}" : "file"}"
      puts

      print_score_table(board)
      puts
      print_score_flags(board)
      print_score_agreement(board)
      print_score_unjudged(board)

      if ENV["SAVE"].present?
        board.save_baseline!
        puts "  baseline rewritten: #{Story::Scoreboard::Baseline::PATH} (#{board.name})"
        puts
      end
    end

    # Per check: how many turns flagged, out of how many it could have flagged,
    # the rate, and the movement since the baseline. A check the corpus cannot
    # answer is UNAVAILABLE rather than 0.0%, which would be a lie that reads
    # like good news.
    def self.print_score_table(board)
      if board.baseline_scenes
        puts "  ! THE CORPUS CHANGED SIZE: #{board.baseline_scenes} turns when the baseline was taken, " \
             "#{board.scanned} now."
        puts "    Rates are still comparable; counts are not, and a corpus that shrank will read"
        puts "    as an improvement nobody made. Re-baseline (SAVE=1) once that is understood."
        puts
      end

      puts format("  %-26s %8s %8s %8s   %s", "check", "flagged", "of", "rate", "vs baseline")
      board.movements.each do |movement|
        reading = movement.now
        puts format("  %-26s %8s %8s %8s   %s",
                    reading.code,
                    reading.available ? reading.flagged : "--",
                    reading.available ? reading.scanned : "--",
                    reading.available ? "#{reading.percentage}%" : "unavailable",
                    movement_note(movement))
      end
      puts
      puts "  A rate is per turn the check could judge, not per turn in the corpus -- see"
      puts "  Story::Audit#judgeable_for. 'unavailable' means this corpus carries no record"
      puts "  the check reads; it is not a zero."

      fired = board.readings.select { |reading| reading.flagged.positive? }
      return if fired.empty?

      puts
      puts "  what each check that fired is counting:"
      fired.each { |reading| puts format("    %-26s %s", reading.code, reading.description) }
    end

    def self.movement_note(movement)
      return "unavailable" unless movement.now.available
      return "new -- no baseline yet" if movement.new_check?
      return "unchanged (#{(movement.then_rate * 100).round(1)}%)" unless movement.moved?

      direction = movement.better? ? "better" : "worse"
      format("%s %+.1f pts (was %.1f%%, %d flag%s)", direction, movement.delta * 100,
             movement.then_rate * 100, movement.then_flagged, movement.then_flagged == 1 ? "" : "s")
    end

    # EVERY FLAG, WITH THE TURN, WHAT HE TYPED AND THE PASSAGE. This is the
    # part that replaces reading the whole log.
    def self.print_score_flags(board)
      if board.flags.empty?
        puts "  Nothing flagged."
        puts
        return
      end

      puts "  #{board.flags.size} flag#{"s" unless board.flags.one?}, worst class first:"
      puts
      board.flags_in_reading_order.each { |flag| print_score_flag(board, flag) }
    end

    def self.print_score_flag(board, flag)
      mark = SCORE_MARKS.find { |predicate, _| flag.public_send(predicate) }&.last || "?"
      turn = flag.scene
      verdict = board.verdicts[turn]

      typed = turn.respond_to?(:typed) ? turn.typed.to_s.strip : ""

      puts "  #{mark} [#{flag.code}] #{score_subject(turn)}#{" -- he called it #{verdict.upcase}" if verdict}"
      puts "      typed: #{typed.presence || no_command_reason(turn)}"
      puts "      #{flag.headline}"

      # The passage, unless it would only repeat the command a line above it --
      # which is what `evidence_line` falls back to for the two checks whose
      # evidence IS what was typed.
      passage = (flag.evidence[:claim].presence || flag.evidence_line).to_s.squish
      puts "      > #{passage}" if passage.present? && passage != typed
      puts
    end

    # WHY A TURN HAS NO COMMAND, told apart rather than guessed at: an opening
    # arrival is world data nobody typed, and a turn written before
    # `Scene#typed` existed lost the words rather than never having them.
    def self.no_command_reason(turn)
      return "(nothing -- an opening arrival, which is world data)" if turn.respond_to?(:is_opening?) && turn.is_opening?

      "(not recorded -- this turn predates Scene#typed)"
    end

    # A turn's name, whichever corpus it came from: a `Scene` has an id and a
    # room, a frozen passage has a label.
    def self.score_subject(turn)
      return "(no turn)" if turn.nil?
      return "#{turn.label}#{" (#{turn.room})" if turn.respond_to?(:room) && turn.room}" if turn.respond_to?(:label)

      "scene ##{turn.id}#{" (#{turn.location&.name})" if turn.location}"
    end

    # AGAINST HIS OWN VERDICTS, and the small-sample caveat is printed in words
    # rather than hidden behind a percentage. See Story::Scoreboard::Agreement.
    def self.print_score_agreement(board)
      if board.labelled.zero?
        puts "  Against his verdicts: no turn in this corpus carries one, so agreement is unmeasured."
        puts
        return
      end

      puts "  Against his verdicts: #{board.labelled} labelled turn#{"s" unless board.labelled == 1} " \
           "(#{board.verdict_tally.map { |v, n| "#{n} #{v}" }.join(", ")})"

      unless board.agreement_established?
        puts "  CORRELATION UNESTABLISHED: #{board.labelled} verdicts is not a correlation and is not"
        puts "  reported as one. The counts below are counts. This line goes away at " \
             "#{Story::Scoreboard::MIN_VERDICTS}, and"
        puts "  the figure recomputes on its own as he labels more turns."
      end

      puts format("    %-26s %6s %6s %6s", "check", "good", "weak", "bad")
      board.agreements.select { |a| a.flagged.positive? }.each do |agreement|
        puts format("    %-26s %6d %6d %6d", agreement.code, agreement.on_good, agreement.on_weak, agreement.on_bad)
      end

      missed = board.missed_verdicts
      if missed.empty?
        puts "    every turn he marked weak or bad was caught by a check."
      else
        puts "    #{missed.size} turn#{"s" unless missed.one?} he marked weak or bad that NO check caught " \
             "-- this is where the next check comes from:"
        missed.each { |turn, verdict| puts "      #{verdict.upcase} #{score_subject(turn)}: #{turn_note(turn)}" }
      end
      puts
    end

    def self.turn_note(turn)
      return turn.note if turn.respond_to?(:note) && turn.note.present?

      Playthrough::Feedback.where(scene_id: turn.id).pick(:note).presence || "(no note)"
    end

    def self.print_score_unjudged(board)
      return if board.unjudged.empty?

      puts "  #{board.unjudged.size} check#{"s" unless board.unjudged.one?} not judged -- the records " \
           "cannot answer them honestly (rake game:audit VERBOSE=1 lists them)"
      puts
    end

    def self.print_score_footer(boards, elapsed)
      turns = boards.sum(&:scanned)
      puts "=" * 78
      puts "#{turns} turn#{"s" unless turns == 1} over #{boards.size} corp#{boards.one? ? "us" : "ora"} " \
           "in #{(elapsed * 1000).round} ms. Nothing here scored prose."
      puts "The two corpora are never added together: one is true and small, the other is"
      puts "frozen and reproducible. See Story::Scoreboard."
      puts
      puts "SAVE=1 rake game:score   record today's numbers as the baseline the next run moves against"
      unless ENV["SAVE"].present?
        puts "Baseline on file: #{File.exist?(Story::Scoreboard::Baseline.path) ? Story::Scoreboard::Baseline::PATH : "none yet"}"
      end
    end

    def self.print_audit_summary(audits, elapsed)
      scanned = audits.sum(&:scanned)
      contradictions = audits.sum { |audit| audit.contradictions.size }
      drifts = audits.sum { |audit| audit.drifts.size }
      limits = audits.sum { |audit| audit.limits.size }
      unjudged = audits.sum { |audit| audit.unjudged.size }
      per_scene = scanned.positive? ? " (#{(elapsed * 1000 / scanned).round(1)} ms per scene)" : ""

      puts "=" * 72
      puts "#{scanned} scene#{"s" unless scanned == 1} in #{(elapsed * 1000).round} ms#{per_scene}"
      puts "#{contradictions} contradiction#{"s" unless contradictions == 1} -- the records say the narration is wrong"
      puts "#{drifts} drift#{"s" unless drifts == 1} -- the player reached for something the records do not have"
      puts "#{limits} line#{"s" unless limits == 1} that named two things -- a turn is one act, so they were refused"
      puts "#{unjudged} check#{"s" unless unjudged == 1} not judged"
      puts
      puts "A contradiction is a defect. A drift is evidence, not proof -- see Playthrough::Drift."
      puts "A line that named two things is neither -- see Playthrough::Overreach."
    end

    def self.timed(label)
      print "#{label}... "
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      puts "done (#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)}s)"
      result
    end

    # Saving the universe cascades to the story built on its association, so
    # the pair lands together or not at all.
    def self.persist!(universe, story)
      ActiveRecord::Base.transaction { universe.save! }
    rescue ActiveRecord::RecordInvalid
      errors = (universe.errors.full_messages + story.errors.full_messages).uniq
      abort "Failed to save the new world: #{errors.join(', ')}"
    end
  end
end
