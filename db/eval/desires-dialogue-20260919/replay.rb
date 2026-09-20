# Offline proof that every retained request and engine fact still comes from
# today's builders. No provider call or budget write is made.
require "json"
require "digest"

root = Pathname.new(__dir__)
manifest = JSON.parse(root.join("source-manifest.json").read)
manifest.fetch("source_files").each do |path, expected|
  actual = Digest::SHA256.file(Rails.root.join(path)).hexdigest
  raise "Producer source changed: #{path}" unless actual == expected
end
result = Eval::Dialogue::Result.load(root)
result.validate_complete!
result.rows.each do |row|
  rebuilt = Eval::Dialogue::Version.rebuild(row)
  raise "Request changed: #{row.values_at('id', 'rep').join(':')}" unless rebuilt.fetch("requests") == row.fetch("requests")
  raise "Engine facts changed: #{row.values_at('id', 'rep').join(':')}" unless rebuilt.fetch("facts") == row.fetch("facts")
  raise "Stored request digest changed" unless Eval::Dialogue::Version.digest(row.fetch("requests")) == row.fetch("request_digest")
end
puts JSON.pretty_generate(offline: true, provider_calls: 0, budget_writes: 0,
  readings: result.rows.size, repetitions: result.data.fetch("reps"), corpus_digest: result.data.fetch("corpus_digest"))
