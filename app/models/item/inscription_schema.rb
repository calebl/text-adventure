# THE WORDS ON ONE THING, and nothing else in the answer.
#
# The smallest schema in the app on purpose. `Item::Inscriber` asks this exactly
# once per readable item that arrived without any words -- a seeded note, a row
# older than the columns -- and what comes back is stored as a record before any
# prose exists. So the call has one job, one field, and one cap, and there is
# nothing in it for a model to spend tokens on that the game does not keep.
#
# IT IS ASKED FOR WHAT IS WRITTEN, NOT FOR A DESCRIPTION OF IT. "A folded note in
# a hurried hand" is what `Item#description` already holds; this field is the
# text a player would read off the thing, and the difference is the whole reason
# the field exists. The narrator is handed it verbatim (`Playthrough::Turn#read_fact`),
# so a paraphrase here is a paraphrase the player reads forever.
#
# The cap is `Item::INSCRIPTION_LIMIT`, which is also the column's ceiling and
# the cap `Location::DetailSchema` asks the same field for. One number, three
# places, so an answer that fits the schema fits the row.
class Item::InscriptionSchema < RubyLLM::Schema
  string :inscription,
         description: "The words written on this thing, exactly as they appear on it, as the player would read them. Not a description of the object and not a narration of reading it -- the text itself. Keep the register and the period of the world. It may be a few words, a line, or a short paragraph.",
         max_length: Item::INSCRIPTION_LIMIT
end
