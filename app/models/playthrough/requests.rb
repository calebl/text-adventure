# THE REQUESTS THE GAME SENDS, BUILT BY THE ENGINE AND BY NOTHING ELSE.
#
# Every turn is played by the Rust engine (`Playthrough::RustEngine`), and the
# engine builds every request that turn sends: the narrator's, a character's
# and the narration of the exchange, the classifier's and System One's, a
# person's volition, an arrival. There is no second copy of those builders in
# Ruby. A bench that measures a request, the Ruby reference loop the test
# suite still plays, and anything else that needs to know what the game would
# send asks here, and the answer is the engine's own bytes.
#
# A REQUEST IS BUILT FROM ROWS, NOT FROM A DATABASE FILE. `.rows` writes every
# row the current connection can see -- inside a transaction too, which is
# where a bench stages a position and where the suite's tests run -- as the
# records the engine's builders read (`EngineVectors::Records` is the same
# format, and the golden vectors are what hold the two readers of it to each
# other). Nothing is written: a request is built, never sent, here.
#
# THE ONE THING THAT PLAYS is `.submit_fixed`: a whole turn on a committed
# database, read as a bench says wherever the classifier would have been
# asked (`Eval::Prompt::Bench`). Every model call a reading or a turn makes
# comes back to the block as the request the engine built, and the block
# answers it (see the extension's `Hosted`); nothing reaches a provider but
# what the block sends.
#
# NO EXTENSION, NO REQUEST. The engine is the only builder, so a process
# without the extension cannot build one, and says so rather than guessing.
module Playthrough::Requests
  # Not rows a builder reads: Rails' own bookkeeping, and RubyLLM's model
  # registry, which is large and read by nothing the engine builds.
  SKIPPED = %w[schema_migrations ar_internal_metadata ruby_llm_models].freeze

  class Unbuilt < StandardError; end

  # One request, by the engine builder's name for it: `narration`,
  # `framing`, `handled_note`, `character`, `interaction_narration`,
  # `classifier`, `cascade`, `volition`, `speech_choices`, `arrival` or `room`. `rows` is a
  # `.rows` document, for a caller building several from one moment.
  def self.build(kind, rows: self.rows, **arguments)
    answered(extension.request(kind.to_s, rows, JSON.generate(arguments)))
  end

  # The narrator's request for `command`, after the turn wrote what it did:
  # `{system, user}`. `doing` is the kind of turn (`scene/narrator.yml`'s
  # `doing`), `handled` the item the turn moved and which way.
  def self.narration(playthrough, command:, fact: nil, doing: nil, handled: nil)
    build(:narration, playthrough: playthrough.id, command: command.to_s, fact: fact, doing: doing&.to_s,
                      handled: handled && { item: handled.fetch(:item).id, direction: handled.fetch(:direction).to_s })
  end

  # What `character` may say unasked in `location`, in the order the engine
  # offers it: `[{token, fact}]`, the fact the narrator would be told.
  def self.speech_choices(playthrough, character, location:)
    build(:speech_choices, playthrough: playthrough.id, character: character.id, location: location.id)
  end

  # A line read the way a turn reads it, over the rows the connection sees:
  # System One first when `system_one`, then the classifier model. Each call
  # is yielded as the engine's request (a Hash) and answered with what the
  # block returns (a Hash). Answers `{intent, resolved_by, target_present,
  # named_more_than_one, calls}`, or, where the block answered a call as a
  # failure, `{error: {kind: "model", ...}, calls}`.
  def self.read_line(playthrough, line, system_one:, rows: self.rows, &block)
    answered(extension.read_line(rows, playthrough.id, line.to_s, system_one) { |call| JSON.generate(block.call(JSON.parse(call))) },
             failed: true)
  end

  # One submitted line played by the engine on the committed database at
  # `database`, read as `fixed` (`{action:, target:}`) says, every call the
  # turn makes answered by the block. Answers the engine's document with
  # `calls`, every request the turn made.
  def self.submit_fixed(database, playthrough, line, token:, fixed:, system_one: false, &block)
    answer = extension.submit_fixed(database.to_s, playthrough.id, line.to_s, token, JSON.generate(fixed), system_one) do |call|
      JSON.generate(block.call(JSON.parse(call)))
    end
    JSON.parse(answer)
  ensure
    ActiveRecord::Base.connection.clear_query_cache
  end

  # The engine's data files, `{name => text}`: what `EngineData` reads.
  def self.data = JSON.parse(extension.data)

  # Every row the connection sees, as the records a builder reads: tables in
  # name order, only tables with rows, rows in id order (or in column order
  # for a table with no id), every column present. A boolean is true/false,
  # a time whole seconds since the Unix epoch, a JSON column its parsed value.
  # `fixed` replaces a column's value in every row of a table, for a caller
  # whose rows must not carry what was rolled at random.
  def self.rows(fixed: {}) = JSON.generate(dump(fixed: fixed))

  def self.dump(fixed: {})
    connection = ActiveRecord::Base.connection
    (connection.tables.sort - SKIPPED).each_with_object({}) do |table, dump|
      columns = connection.columns(table).sort_by(&:name)
      arel = Arel::Table.new(table)
      order = columns.any? { |column| column.name == "id" } ? [ arel[:id] ] : columns.map { |column| arel[column.name] }
      rows = connection.select_all(arel.project(Arel.star).order(*order)).to_a
      next if rows.empty?

      replaced = fixed.fetch(table, {})
      dump[table] = rows.map do |row|
        columns.to_h { |column| [ column.name, replaced.fetch(column.name) { value(column, row[column.name]) } ] }
      end
    end
  end

  def self.value(column, raw)
    return nil if raw.nil?

    case column.type
    when :boolean then ActiveModel::Type::Boolean.new.cast(raw)
    when :datetime then ActiveRecord::Type::DateTime.new.cast(raw).to_i
    when :json then raw.is_a?(String) ? JSON.parse(raw) : raw
    else raw
    end
  end

  def self.extension
    Playthrough::RustEngine.extension or
      raise Unbuilt, "the engine builds every request, and its extension is not built or did not load " \
                     "(#{Playthrough::RustEngine.load_error}); run bin/rails engine:build"
  end

  # A document naming an error is raised, but for a model failure a caller
  # asked to see (`failed:`): that is the caller's own block's answer.
  def self.answered(document, failed: false)
    parsed = JSON.parse(document)
    if parsed.is_a?(Hash) && (error = parsed["error"]).is_a?(Hash) && error.key?("kind") &&
       !(failed && error["kind"] == "model")
      raise Unbuilt, "the engine could not build that request: #{error["message"]}"
    end

    parsed
  end

  private_class_method :answered, :value
end
