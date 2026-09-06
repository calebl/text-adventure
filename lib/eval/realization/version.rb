# WHICH PROMPT BUILT THIS SET, as two digests and one guard.
#
# THE PROBLEM IT SOLVES is `Eval::Prompt::Version`'s: this bench exists to judge
# prompt-shaped changes, so "which prompt" has to be a field on the set and not
# a thing somebody remembers -- the same job `corpus_digest` does for the cases.
# And a realization prompt is instructions AND facts interleaved, so a digest of
# the whole thing would give every room its own version and group nothing.
#
# SO THERE ARE TWO, AND THEY COVER DIFFERENT AMOUNTS:
#
#   `instructions_digest`  the system message -- `Location::Generator#system_prompt`,
#                          which is the same three sentences for every room in
#                          every world. It covers the instruction block and
#                          nothing else.
#
#   `prompt_digest`        BOTH USER PROMPTS, byte for byte, for ONE DESIGNATED
#                          CASE PER SHAPE -- the lowest case id of that shape.
#                          It therefore covers everything the instructions
#                          digest misses, which here is almost all of it:
#                          `#items_instructions`, `#people_instructions`,
#                          `#known_names_note`, `#already_reachable_note` and
#                          the exits instructions are the three prompts this
#                          bench was built to measure, and every one of them
#                          lives in a user message.
#
# AND ONE LINE IS SCRUBBED BEFORE THE DIGEST IS TAKEN, which is the whole of
# what makes `stable` mean anything here.
#
# `Character::Registry#slots` rolls the race, age and sex of each person the
# call may name, and `Location::Generator#slot_details` states them in the
# prompt. Two of those three are NOT SEEDED AT ALL -- `rand(18..80)` and
# `Character.sexes.values.sample` are Kernel's own generator -- and the third is
# seeded on `story_id` and `location.id`, which a staged copy of a world
# re-issues on every load. So those lines legitimately differ between two
# repetitions of one case, and a digest over them would call every run a
# different prompt version and every run unstable.
#
# THEY ARE SCRUBBED RATHER THAN PINNED, and that is a deliberate choice about
# where the honesty goes. Pinning them would mean this file re-implementing
# `#slots` -- a second implementation of the one thing in the app that decides
# who a new person is, which is precisely the "two implementations, two answers"
# failure every other file here is written to avoid. What the bench does instead
# is RECORD what was offered (`Eval::Realization::Stage::Standing#slots`) and
# score against that, so `people_offered` is a measured denominator rather than
# an assumed one. What it costs is stated rather than hidden: the cast details
# are the one input to this bench that is not identical between repetitions, and
# a figure that turned on WHICH race a slot drew would need more repetitions
# than one that does not.
#
# EVERYTHING ELSE IN THE PROMPT IS SUPPOSED TO BE CONSTANT -- the universe, the
# preface, the room, the teaser, the allowances, the places that already exist,
# the names already spoken for -- and `stable` is the check on that claim.
# Every repetition of every arm sends the designated case's prompts again and
# they are compared: if one case ever produced two different scrubbed prompts in
# one run, something in the staging is not constant and every figure in the set
# is suspect. Reported rather than raised -- a run that cost money should print
# what it found -- and the board says so loudly.
module Eval::Realization::Version
  extend self

  # THE ROLLED LINE, as `Location::Generator#slot_details` writes it:
  # `  the 1st is Shorefolk, about 44, woman`. Anchored to the start of the line
  # and to the ordinal so that nothing else in a prompt can match it.
  ROLLED_CAST_LINE = /^ {2}the \d+(?:st|nd|rd|th) is .*$/

  SCRUBBED = "  <the engine's own roll -- see Eval::Realization::Version>".freeze

  def scrub(prompt) = prompt.to_s.gsub(ROLLED_CAST_LINE, SCRUBBED)

  # The digests a run records, computed off the readings it collected -- the
  # live `Eval::Realization::Bench::Reading`s, because they are the only place
  # the instruction text itself is held. A stored row keeps the DIGEST and the
  # prompts, not the instruction block: repeating three unchanging sentences on
  # every row is a file nobody wants.
  def of(passes)
    readings = Array(passes).flat_map(&:readings).reject(&:failed?)

    prompts = designated(readings)
    { prompt_digest: digest(prompts.map { |shape, sent| "#{shape}\n#{sent.first}" }),
      prompt_shapes: prompts.transform_values { |sent| Playthrough::PromptVersion.of(sent.first) },
      prompt_stable: prompts.values.all? { |sent| sent.uniq.one? },
      instructions_digest: digest(instructions(readings)) }
  end

  # ONE CASE PER SHAPE, AND THE SAME ONE EVERY RUN: the lowest case id of that
  # shape that actually produced prompts. Chosen by id rather than by position
  # in the file so that reordering the corpus does not silently change the
  # version. Both calls' prompts are joined, in the order the app sends them.
  def designated(readings)
    readings.reject { |reading| reading.prompts.blank? }
            .group_by { |reading| reading.shape.to_s }
            .transform_values { |scoped|
              chosen = scoped.map(&:id).min
              scoped.select { |reading| reading.id == chosen }.map { |reading| sent(reading) }
            }
            .sort.to_h
  end

  # BOTH PROMPTS OF ONE READING, scrubbed, in the app's own call order.
  def sent(reading)
    Eval::Realization::CALLS.filter_map { |call| reading.prompts[call] }
                            .map { |prompt| scrub(prompt) }.join("\n \n")
  end

  # Every distinct instruction block the run sent, in a fixed order. One is the
  # ordinary answer: both calls of a realization are one conversation with one
  # system message.
  def instructions(readings) = readings.filter_map(&:instructions).uniq.sort

  def digest(parts)
    body = Array(parts).join("\n \n")
    body.strip.empty? ? nil : Digest::SHA256.hexdigest(body).first(16)
  end
end
