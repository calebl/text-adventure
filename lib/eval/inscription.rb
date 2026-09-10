# ONE FIRST-READ CALL, not a turn. The prompt bench deliberately rejects an
# uninscribed readable item: playing that turn would buy inscription AND prose.
# This sibling calls Item::Inscriber itself and keeps raw answers beside stored
# words. No narrator, classifier, warmup, or new lab UI belongs in this slice.
module Eval::Inscription
  CORPUS = Rails.root.join("test/fixtures/files/inscription_corpus.yml")
  RESULTS = "inscription.json".freeze
  BASELINE = "inscription-2026-09-10".freeze

  def self.cases
    document = YAML.safe_load_file(CORPUS)
    document.fetch("items").flat_map do |item|
      document.fetch("whereabouts").map { |place| item.merge("id" => "#{item.fetch('id')}-#{place}", "whereabouts" => place) }
    end
  end

  def self.digest
    files = [ CORPUS ] + cases.map { |kase| WorldSeed::DIRECTORY.join("#{WorldSeed.slug(kase.fetch('story'))}.yml") }.uniq
    Digest::SHA256.hexdigest(files.map { |file| File.read(file) }.join("\n"))
  end

  def self.stage(kase)
    position = Eval::Classifier::Corpus::Position.new(id: kase.fetch("id"), story: kase.fetch("story"), room: kase.fetch("room"))
    Eval::Classifier::Stage.open([ position ], label: "inscription bench", retitle: true) do |stages|
      standing = stages.fetch(position.id)
      game = standing.playthrough
      story = game.story
      templates = Item.where(playthrough_id: nil, name: kase.fetch("item"))
      template = templates.detect { |item| item.location&.story == story || item.character&.story == story }
      raise ArgumentError, "missing readable seed item: #{kase}" unless template&.readable?

      template.update!(inscription: nil)
      item = game.items.find_by(template: template) || template.dup.tap { |copy| copy.update!(playthrough: game, template: template) }
      holder = story.characters.find_by!(fullname: kase.fetch("holder"))
      place = kase.fetch("whereabouts")
      raise ArgumentError, "unknown whereabouts #{place}" unless %w[room holder carried].include?(place)

      item.update!(inscription: nil, character: place == "holder" ? holder : nil,
                   location: place == "room" ? standing.location : nil, x: nil, y: nil)
      yield Item::Inscriber.new(item, playthrough: game)
    end
  end

  # Only surrogate row IDs are normalized. The actual request is retained too;
  # no world wording, user scaffold, system instruction or schema is scrubbed.
  # Item#whereabouts exposes IDs which vary with the scratch database's history.
  def self.request(inscriber)
    prompt = inscriber.send(:prompt).gsub(/playthrough #\d+'s copy of #\d+/, "playthrough #GAME's copy of #TEMPLATE")
    Eval::RequestIdentity.request(Item::Inscriber::INSTRUCTIONS, prompt, Item::InscriptionSchema)
  end

  def self.requests
    cases.to_h { |kase| [ kase.fetch("id"), stage(kase) { |inscriber| request(inscriber) } ] }
  end

  # Token estimates are conservative byte counts, not measured tokenization.
  # Output includes a schema envelope allowance. Registry absence is an error,
  # never a zero-price invitation to run. No sampling parameter is changed.
  def self.estimate(model: Eval::Cost.default_model, reps: Eval::Noise::MIN_RUNS)
    price = Eval::Cost.price(model)
    raise ArgumentError, "unpriced model; run rake ruby_llm:load_models" if price == Eval::Cost::UNKNOWN

    input = requests.values.sum { |request| JSON.generate(request).bytesize } * reps
    output = cases.size * reps * (Item::INSCRIPTION_LIMIT + 100)
    { model: model, reps: reps, cases: cases.size, input_tokens: input, output_tokens: output,
      dollars: price.of(input, output), price: price.to_h }
  end
end
