# A bounded reading of one character's durable experience in one game.
#
# Interaction already stores the memory; duplicating it into a second model
# would create two accounts of the same conversation. Read beyond the recent
# chat window, rank by the present subject, and collapse repeated resolutions
# before spending the prompt budget. A routine exchange must not evict a promise
# merely because it was written later.
#
# These are RECOLLECTIONS, not world facts. The player's words are attributed,
# the character's resolution is a belief held then, and the Interaction remains
# the source. Only the character's own exchanges on this game's scene chain are
# eligible. No narrator summary, another NPC's thoughts, or another game's rows
# can become this character's knowledge.
#
# Retrieval is lexical, not a claim to understand importance. Matching terms
# from the current line and the character's possessions rank first. Rarer terms
# break ties before recency, so repeated small talk does not crowd out distinct
# experiences. Paraphrases without shared terms can still be missed; the paid
# experience corpus measures behavior beyond this deterministic selection.
class Playthrough::Memory
  STOP_WORDS = %w[a an and are as at be been but by did do does for from had has
                  have he her him his how i if in is it its me my of on or our
                  she so that the their them they this to was we were what when
                  where which who why will with would you your].freeze

  attr_reader :playthrough, :character

  def initialize(playthrough, character)
    @playthrough = playthrough
    @character = character
  end

  # Return actual source rows, so callers can keep attribution with the text.
  # Recent exchanges are already replayed verbatim by the durable chat.
  def recall(query: nil, replayed: Chat::HISTORY_EXCHANGES, limit: Playthrough::Moment::CONCLUSIONS)
    rows = exchanges
    count = [ replayed.to_i, 0 ].max
    rows = rows[0...-count] || [] if count.positive?
    rows = rows.reverse.uniq do |row|
      [ row.user_input.to_s.downcase.strip, row.action.to_s.downcase.strip, resolution(row).downcase,
        (row.action_fact if row.action_status == "applied") ]
    end.reverse
    return [] if rows.empty?

    terms = rows.to_h { |row| [ row.id, words([ row.user_input, row.action, resolution(row), row.action_fact ].join(" ")).uniq ] }
    frequencies = terms.values.flatten.tally
    subjects = words([ query, *playthrough.items_held_by(character).pluck(:name) ].join(" ")).uniq
    ranked = rows.sort_by do |row|
      vocabulary = terms.fetch(row.id)
      relevant = (vocabulary & subjects).sum { |term| rarity(frequencies.fetch(term), rows.size) }
      distinct = vocabulary.sum { |term| rarity(frequencies.fetch(term), rows.size) }.fdiv([ vocabulary.size, 1 ].max)
      [ -relevant, -distinct, -row.id ]
    end
    ranked.first(limit)
  end

  def resolution(row) = (row.inner_resolution.presence || row.action).to_s.strip

  def recollection(row)
    pieces = []
    pieces << %(You heard #{playthrough.character&.fullname || "the speaker"} say: "#{row.user_input.to_s.truncate(100)}") if row.user_input.present?
    if row.action.present? && row.action.to_s.strip != resolution(row)
      pieces << %(You remember responding: "#{row.action.to_s.truncate(200)}")
    end
    pieces << %(You then concluded: "#{resolution(row)}")
    if row.action_status == "applied" && row.action_fact.present?
      pieces << "The recorded result was: #{row.action_fact}"
    end
    pieces.join(" ")
  end

  private

  def exchanges
    return [] unless character.story_id == playthrough.story_id && character != playthrough.character

    Interaction.where(character: character, scene_id: playthrough.scene_chain.map(&:id)).order(:id).to_a
  end

  def words(text)
    text.to_s.downcase.scan(/[[:alnum:]]+/).reject { |term| term.length < 3 || STOP_WORDS.include?(term) }
  end

  def rarity(frequency, total) = Math.log(1 + total.fdiv(frequency))
end
