# THE WORLD EVERY RUN STARTS FROM, built once and copied per run.
#
# `bin/rails runner script/eval_base.rb` writes `tmp/eval/base.sqlite3`: the
# app's schema, the RubyLLM model registry, and the three seeded worlds. Every
# run of a sweep gets a byte-identical copy of it, which is what makes two runs
# comparable -- an arm that started from a world somebody had already walked
# around in is measuring a different world.
#
# It is deliberately NOT `storage/development.sqlite3`. That file accumulates:
# a generated room here, a playthrough there, and a sweep run against it would
# drift a little further from the last one every time.
#
# Offline. No model call, no API key, no network -- `db/seeds.rb`'s two halves
# both read files on disk.
require "fileutils"

path = ENV.fetch("EVAL_BASE", Rails.root.join("tmp/eval/base.sqlite3").to_s)
FileUtils.mkdir_p(File.dirname(path))

if File.exist?(path) && ENV["REBUILD"] != "1"
  warn "  base world already at #{path} (REBUILD=1 to make it again)"
  exit 0
end

FileUtils.rm_f(path)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: path, timeout: 15_000, pool: 5)

# What `db:schema:load` does, against the connection just established.
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

RubyLLM.models.load_from_json!
Model.save_to_database
stories = WorldSeed::Loader.load_all(io: nil)

missing = Eval::STORIES - stories.map(&:title)
abort "the seeded worlds are missing #{missing.join(", ")} -- Eval::STORIES names a world db/seeds/worlds has not got" if missing.any?

warn "  base world at #{path}: #{Model.count} models, #{stories.size} worlds (#{stories.map(&:title).sort.join(", ")})"
