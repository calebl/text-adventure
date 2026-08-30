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

    puts
    puts "=" * 72
    puts story.title
    puts "#{story.genre} -- universe ##{universe.id}, story ##{story.id}"
    puts "=" * 72
    puts
    puts story.preface
    puts
    puts "Add a character with: rails runner \"Story.find(#{story.id}).create_character\""
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
      puts "     universe ##{story.universe_id}  characters: #{story.characters.count}  locations: #{story.locations.count}  scenes: #{story.scenes.count}"
    end
  end

  # Namespaced under a module rather than defined at rake top level, where
  # they would land on Object -- `save!` in particular collides badly there.
  module Helpers
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
