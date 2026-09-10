# Offline completion of this purchase, not another run. The purchased answers
# are unchanged. Recover pre-Deadline admission receipts through the engine,
# then rescore the full rows (including exits-only scans) before keeping them.
require "zlib"
root = Eval.kept_root.join("branches-to-corpus-after")
raise "already finalized" if root.join("admissions.json").exist?
raw = root.join("readings.json.gz")
document = Zlib::GzipReader.open(raw) { |file| JSON.parse(file.read) }
source = Digest::SHA256.file(raw).hexdigest
admissions = []
document.fetch("passes").each do |pass|
  pass.fetch("readings").each do |row|
    next unless row.dig("facts", "quest_request") && row["error"].nil?

    admitted = Eval::Realization::Admissions.replay(row)
    row.fetch("after")["quest_admitted"] = admitted
    admissions << { id: row.fetch("id"), rep: row.fetch("rep"), admitted: admitted,
                    final_bound: row.dig("after", "quest_bound") }
  end
  pass.merge!(Eval::Realization::Result.figures_of(pass.fetch("readings")))
end
Zlib::GzipWriter.open(raw) { |file| file.write(JSON.generate(document)) }
File.write(Eval.root.join("branches-to-corpus-after/realization.json"), JSON.pretty_generate(document))
Eval::Realization::Result.load(Eval.root.join("branches-to-corpus-after")).summary.write!(root)
File.write(root.join("admissions.json"), JSON.pretty_generate({ source_sha256: source, model_calls: 0, admissions: admissions }))
puts "Recovered pre-Deadline admissions and rescored retained answers with no model calls."
