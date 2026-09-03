namespace :game do
  desc "Generate a new universe and story. Usage: rake 'game:new[a heist on a generation ship]'"
  task :new, [ :premise ] => :environment do |t, args|
    premise = args[:premise]

    puts "Premise: #{premise.presence || "chosen by the model"}"
    puts "Model:   #{BaseAgent.default_model_options.first[:model]}"
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

  desc "Score the game against the errors that can be checked. Usage: rake game:score, SAVE=1 to re-baseline, CORPUS=database|corpus"
  task :score, [ :story_id ] => :environment do |t, args|
    boards =
      if args[:story_id]
        [ Story::Scoreboard.database(Story.where(id: Helpers.story!(args[:story_id]).id)) ]
      else
        Story::Scoreboard.all
      end
    boards.select! { |board| board.name == ENV["CORPUS"] } if ENV["CORPUS"].present?

    if boards.empty?
      puts "No corpus to score. CORPUS must be one of: database, corpus."
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
         "#{Item.for_character(playthrough.character).order(:id).pluck(:name).presence&.join(", ") || "nothing"}."
    puts "Pick it up again with: PLAYTHROUGH=#{playthrough.id} rake 'game:mechanics[#{story.id}]'"
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
    # Where items ARE is world state and is shared either way: something left in
    # the closet in one session is still in the closet in the next one, and in
    # the browser. That is the thing being tested, so it is not isolated.
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
    # uses, plus one for pacing, which is not a defect and must not read like
    # one.
    SCORE_MARKS = { contradiction?: "X", defect?: "X", drift?: "~", pacing?: "-" }.freeze

    def self.print_scoreboard(board)
      puts "=" * 78
      puts "CORPUS: #{board.name}"
      puts "  #{board.note}" if board.note
      puts "  #{board.scanned} turn#{"s" unless board.scanned == 1} across #{board.audits.size} " \
           "#{board.name == "corpus" ? "file" : "stor#{board.audits.one? ? "y" : "ies"}"}"
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
      unjudged = audits.sum { |audit| audit.unjudged.size }
      per_scene = scanned.positive? ? " (#{(elapsed * 1000 / scanned).round(1)} ms per scene)" : ""

      puts "=" * 72
      puts "#{scanned} scene#{"s" unless scanned == 1} in #{(elapsed * 1000).round} ms#{per_scene}"
      puts "#{contradictions} contradiction#{"s" unless contradictions == 1} -- the records say the narration is wrong"
      puts "#{drifts} drift#{"s" unless drifts == 1} -- the player reached for something the records do not have"
      puts "#{unjudged} check#{"s" unless unjudged == 1} not judged"
      puts
      puts "A contradiction is a defect. A drift is evidence, not proof -- see Playthrough::Drift."
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
