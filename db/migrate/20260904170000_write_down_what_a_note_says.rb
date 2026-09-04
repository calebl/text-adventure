class WriteDownWhatANoteSays < ActiveRecord::Migration[8.1]
  # WHAT IS WRITTEN ON A THING, as a column on the thing.
  #
  # A note, a letter, a sign, a label: the words on it are the whole of what it
  # is, and until now the app held none of them. `Playthrough::Moment` told the
  # narrator that a "folded note" was lying here and nothing else, so the prose
  # invented what it said -- "Midnight. The Bell. They know about the maps." --
  # with no record to keep it, and the next reading was free to say anything.
  # That is the same failure `take` had before `Item#character` was the answer
  # to "does the player have it": a fact the game depends on, held only in a
  # paragraph.
  #
  # `readable` is whether this thing HAS words on it at all, and it gates
  # everything: nothing is ever generated for an item that is not marked
  # readable, so a ward stamp never grows an inscription by accident.
  # `inscription` is those words, verbatim, bounded at
  # `Item::INSCRIPTION_LIMIT`.
  #
  # REAL COLUMNS RATHER THAN `items.properties`, which already holds a JSON
  # blob and could have carried both. The blob cannot be queried: `rake
  # game:doctor` has to be able to ask which readable items have no words yet,
  # `WorldSeed::Loader` has to round-trip them, and `Story::Audit` has to read
  # one beside a `Scene`. A fact three offline instruments read is a column.
  #
  # `inscription` IS NULLABLE AND STAYS NULLABLE. Every item written before
  # this migration has none; a readable item seeded or realized without one
  # gets its words written once, on the first read, by `Item::Inscriber`. A
  # non-readable item may never have one at all, which `Item` validates.
  # NO INDEX ON `readable`, deliberately. Every question the app asks of it is
  # asked of ONE row the classifier has already resolved (`Item#readable?`), and
  # the only set query is `Item.readable` / `.unwritten` for a report about a
  # whole world -- which is a scan of a table that holds at most
  # `Item::Registry::MAX_PER_STORY` rows per story. An index on a two-valued
  # column with no query behind it is a write cost nothing pays for.
  def change
    add_column :items, :readable, :boolean, null: false, default: false
    add_column :items, :inscription, :text
  end
end
