# Offline, no model: the request the classifier is sent at every labelled
# position's first line, written to OUT as { position => user prompt }.
# Run once with the checked-in seeds and once with the pre-arc seeds in place,
# then diff, to see which positions the seed edits changed.
corpus = Eval::Classifier.corpus
out = corpus.positions.to_h do |position|
  subset = corpus.subset { |line| line.position == position.id }
  request = Eval::Classifier::Version.requests(subset).values.first
  [ position.id, request[:user] ]
end
File.write(ENV.fetch("OUT"), JSON.pretty_generate(out) + "\n")
puts "#{out.size} positions"
