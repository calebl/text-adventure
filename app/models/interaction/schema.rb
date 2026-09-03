# One character's reaction to what the player said or did. InteractionAgent
# interpolates all five fields into the narrator prompt by string key, so the
# names here are a hard contract with InteractionAgent#narrator_instructions.
#
# Lengths are explicit on every field, and they matter more here than anywhere
# else in the app: this is the only schema that runs once per turn of dialogue,
# so an unbounded field has no ceiling on what a conversation costs. It is also
# the schema that used to have no bounds at all -- the same omission that once
# had a strong model answer "Race of the character" with 2,382 characters.
class Interaction::Schema < RubyLLM::Schema
  # THE CAP IS A CEILING ON RUNAWAY OUTPUT, NOT THE SHAPE OF THE ANSWER. The
  # description says the shape -- one sentence, two or three words -- and the
  # cap is set well clear of what that shape costs, because a cap set AT the
  # shape does not shorten the answer, it cuts it in half. Real rows proved it:
  # one `pre_feeling` came back at exactly 60 characters ending "hopeful for a
  # (v", its `pre_thought` at exactly 200, another `pre_thought` ending "so as
  # not to r". The narrator pass then wrote fluent prose over the fragments, so
  # nobody reading the game could tell.
  #
  # The numbers are what the requested shape actually measures, doubled:
  # narrative English runs ~150 characters to the sentence and an emotion word
  # ~12, so a sentence gets 320, two sentences 480, and three comma-separated
  # words 120. An answer that reaches one of these did not write to the shape,
  # and `SanitizesGeneratedText` treats reaching one as truncation -- which is
  # only a safe reading because the headroom is this wide.
  MAX_LENGTHS = {
    pre_thought: 320,
    pre_feeling: 120,
    action: 480,
    post_feeling: 120,
    post_thought: 320,
    inner_resolution: 320
  }.freeze

  string :pre_thought,
         description: "What you thought immediately in response to what was just said or done to you. " \
                      "One sentence, at most 320 characters.",
         max_length: MAX_LENGTHS[:pre_thought]
  string :pre_feeling,
         description: "What you felt immediately in response to what was just said or done to you. " \
                      "Two or three words, comma separated, at most 120 characters.",
         max_length: MAX_LENGTHS[:pre_feeling]
  string :action,
         description: "What you did and said in response. Speech goes inside quotes. " \
                      "One or two sentences, at most 480 characters.",
         max_length: MAX_LENGTHS[:action]
  string :post_feeling,
         description: "What you felt after you took the action. " \
                      "Two or three words, comma separated, at most 120 characters.",
         max_length: MAX_LENGTHS[:post_feeling]
  string :post_thought,
         description: "What you thought after you took the action. " \
                      "One sentence, at most 320 characters.",
         max_length: MAX_LENGTHS[:post_thought]
  # WHAT THEY DECIDED, as opposed to what they did. `Interaction#completed?`
  # reads it and was therefore always false, because nothing had ever written
  # one -- the ROADMAP called it "a second call nothing asks for yet", and a
  # second call per line of dialogue is the most expensive way to get one
  # sentence. It is a sixth field on a call that already happens instead: no
  # extra round trip, ~30 tokens.
  #
  # It is deliberately NOT interpolated into the narrator pass. A resolution is
  # about what the character will do next, and handing it to the narrator invites
  # it to narrate that instead of the moment -- the character acting on a
  # decision they have only just made, before the player has done anything.
  string :inner_resolution,
         description: "What you decided to do as a result of this exchange. " \
                      "One sentence, at most 320 characters.",
         max_length: MAX_LENGTHS[:inner_resolution]

  # The cap this schema asked `field` to stay under, for a caller sanitizing the
  # answer. Raises on a field this schema does not describe rather than
  # returning nil: nil would silently turn the truncation check off, which is
  # exactly the failure this whole arrangement exists to catch.
  def self.max_length_for(field)
    MAX_LENGTHS.fetch(field.to_sym)
  end
end
