# WHAT A CHECKOUT HAS TO DO AFTER IT PULLS. `bin/update` calls this; the list
# itself is `lib/update.rb` and its header is how a PR adds to it.
namespace :game do
  desc "Apply everything the code you just pulled needs done to your database. Usage: rake game:update, DRY_RUN=1 to see it first, ONLY=<step>"
  task update: :environment do
    dry = ENV["DRY_RUN"].present?
    steps = UpdateHelpers.steps!(ENV["ONLY"])

    puts "POST-UPDATE STEPS: #{steps.size} of #{Update::REGISTRY.size}, in dependency order."
    puts "Offline -- no model call, no network, no key. Every step is safe to run again."
    puts "DRY RUN: nothing is written." if dry
    puts

    runner = Update::Runner.new(
      steps: steps,
      dry_run: dry,
      allow_model_calls: ENV["ALLOW_MODEL_CALLS"].present?,
      verbose: ENV["VERBOSE"].present?
    )
    runner.run

    puts
    changed = runner.changed
    if runner.failed?
      # Flushed before the abort, which writes to stderr: a log that interleaves
      # the two would put the verdict above the step it is about.
      $stdout.flush
      abort "FAILED at #{runner.failed.step.key}. Nothing after it ran, because the steps are in " \
            "dependency order and a later one would read a half-updated database."
    elsif changed.empty?
      puts "Nothing to do: this database already has everything the code needs."
    elsif dry
      puts "#{changed.size} step(s) WOULD do something: #{changed.map { |outcome| outcome.step.key }.join(", ")}."
      puts "Nothing was written. Drop DRY_RUN=1 to do it."
    else
      puts "#{changed.size} step(s) did something: #{changed.map { |outcome| outcome.step.key }.join(", ")}."
    end
  end

  namespace :update do
    desc "List the post-update steps in the order they run, and why each one is there"
    task list: :environment do
      Update::REGISTRY.each { |step| puts "  #{step.key} -- #{step.reason}" }
    end
  end

  # Namespaced under a module rather than defined at rake top level, where it
  # would land on Object -- the same reason `game.rake` has `Helpers`, under a
  # different name because rake loads every file in `lib/tasks` into one scope.
  module UpdateHelpers
    # The registry, or the one step `ONLY=` named. Unknown names abort with the
    # list rather than running everything or nothing.
    def self.steps!(only)
      return Update::REGISTRY if only.blank?

      wanted = only.to_s.split(",").map { |name| name.strip.to_sym }
      unknown = wanted - Update::REGISTRY.map(&:key)
      if unknown.any?
        abort "No update step #{unknown.map(&:to_s).join(", ")}. There is: " \
              "#{Update::REGISTRY.map(&:key).join(", ")}."
      end

      Update::REGISTRY.select { |step| wanted.include?(step.key) }
    end
  end
end
