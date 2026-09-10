# One designated position (lowest labelled line id), rebuilt from the corpus.
# Names and set sizes are seed-owned, not random: retain them so changing a
# closed-set label moves the identity. Database ids never enter the request.
# The typed value is fixed to that line; literal list framing is never scrubbed.
module Eval::Classifier::Version
  extend self

  def offline(corpus = Eval::Classifier.corpus)
    Eval::RequestIdentity.of(requests(corpus))
  end

  def offline_details(corpus = Eval::Classifier.corpus)
    sent = requests(corpus)
    { request_identity: Eval::RequestIdentity.of(sent),
      instructions_digest: Eval::Prompt::Version.digest(sent.values.map { |request| request[:system] }),
      prompt_digest: Eval::Prompt::Version.digest(sent.values.map { |request| request[:user] }) }
  end

  def requests(corpus = Eval::Classifier.corpus)
    line = corpus.lines.min_by(&:id)
    request = nil
    EngineSweep.without_a_model do
      Eval::Classifier::Stage.open([ corpus.position(line.position) ]) do |stages|
        classifier = stages.fetch(line.position).classifier
        exits, cast, items, carried = classifier.exits_here, classifier.characters_here,
                                     classifier.items_here, classifier.items_carried
        names = classifier.send(:exit_names, exits) + classifier.send(:cast_names, cast) +
                classifier.send(:item_names, items) + classifier.send(:item_names, carried)
        request = Eval::RequestIdentity.request(
          Playthrough::Classifier::INSTRUCTIONS,
          classifier.command_prompt(line.typed, exits, cast, items, carried),
          Playthrough::IntentSchema.for(names)
        )
      end
    end
    { line.id => request }
  end
end
