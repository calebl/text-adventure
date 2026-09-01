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

  # Namespaced under a module rather than defined at rake top level, where
  # they would land on Object -- `save!` in particular collides badly there.
  module Helpers
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
