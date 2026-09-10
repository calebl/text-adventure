# Legacy identities below are frozen for kept-set compatibility. Their broad
# scrub is NOT used by RequestVersion, which fixes only rolled inputs before
# rendering and retains all direction wording in the schema-aware identity.
#
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
# AND TWO KINDS OF LINE ARE SCRUBBED BEFORE THE DIGEST IS TAKEN, which is the
# whole of what makes `stable` mean anything here. Both are the engine's own
# dice, and a die is not a version of a prompt.
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
# AND SO IS THE COUNT THE PEOPLE BLOCK ASKS FOR, one paragraph up's reason
# exactly. Since the captain's ruling of 2026-09-07 the narrator picks how
# populated a place is from a closed list on the exits call of the room next
# door, and the engine rolls the number that word means
# (`Location::Population`). A room a seed file left silent about carries no word,
# so the LABEL is rolled as well -- keyed on the room's own id, which a staged
# copy of a world re-issues on every load, exactly like the race above. So the
# count legitimately differs between two repetitions of one case, and a digest
# over it would call every run a different prompt version and every run
# unstable.
#
# IT IS SCRUBBED BY POSITION AND NOT BY WORDING: the line under `## Who Is
# Here`, whichever of the two sentences `Location::Generator#people_instructions`
# put there. That is why the heading is kept over both branches -- a scrub that
# matched the sentence would stop matching the moment somebody reworded it, which
# is the one thing this file exists to notice. THE REST OF THE BLOCK IS STILL
# COVERED: the bullets, the slot preamble and the nought branch's second line are
# all inside the digest, so a reworded instruction moves the version and a
# different roll does not.
#
# WHAT IS NOT LOST BY SCRUBBING IT: the count is RECORDED rather than assumed --
# `Eval::Realization::Stage::Standing#people_allowance` -- so `people_offered` is
# a measured mean and `people_take_up` a ratio over what was actually asked for.
# The bench can therefore still answer the question the ruling was made to fix,
# *does the model write the people the engine asked for*, across a spread of
# counts rather than at one.
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
#
# AND THE SAME DIGEST CAN BE TAKEN WITHOUT SPENDING ANYTHING -- `.offline`,
# which is the half of this module the captain's standing rule of 2026-09-06
# actually needs. *"We should always have a baseline for evaluating a prompt
# before we decide to change it"* has a question in front of it that nobody
# could answer for free until this method: **is the baseline on disk still a
# baseline for the prompts in this tree?** `#of` can only answer it by buying a
# run, so the answer was a thing somebody remembered.
#
# IT WORKS BECAUSE A PROMPT IS BUILT BEFORE IT IS SENT. `Location::Generator`'s
# `#detail_prompt`, `#exits_prompt` and `#system_prompt` are pure readers over a
# staged world -- the same objects `Eval::Realization::Stage` stands up for a
# real pass -- so the bytes a run WOULD send can be assembled with no key, no
# network and no model. What it cannot do is measure anything: it says which
# prompt, never how well it did.
#
# THE ONE THING IT MUST NOT DO IS DERIVE THE DIGEST A SECOND WAY. Both halves
# below go through `#digest`, `#scrub` and the same designation rule -- lowest
# case id per shape -- so an offline digest and a bought one are the same string
# or the prompts really moved. `Eval::Realization::KeptSetTest` is what asserts
# that of the checked-in set, which is how a prompt edited without a
# re-baseline becomes a failing test rather than a thing nobody noticed.
module Eval::Realization::Version
  extend self

  # Legacy designation stays fixed when branch fixtures are added. BranchRequests
  # identities cover their full requests separately, including restored history.

  # THE ROLLED LINE, as `Location::Generator#slot_details` writes it:
  # `  the 1st is Shorefolk, about 44, woman`. Anchored to the start of the line
  # and to the ordinal so that nothing else in a prompt can match it.
  ROLLED_CAST_LINE = /^ {2}the \d+(?:st|nd|rd|th) is .*$/

  SCRUBBED = "  <the engine's own roll -- see Eval::Realization::Version>".freeze

  # THE ROLLED COUNT, BY POSITION: the heading `Location::Generator` writes over
  # both branches of the people block, and the one line under it. Anchored on the
  # heading so that the items and exits allowances -- read off the records rather
  # than rolled, and supposed to be constant -- go on being covered.
  ROLLED_PEOPLE_LINE = /^(## Who Is Here\n).*$/

  COUNT_SCRUBBED = "\\1<the engine's own roll -- see Eval::Realization::Version>".freeze

  def scrub(prompt)
    prompt.to_s.gsub(ROLLED_CAST_LINE, SCRUBBED).gsub(ROLLED_PEOPLE_LINE, COUNT_SCRUBBED)
  end

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

  # THE SAME TWO DIGESTS, WITH NO MODEL CALL AND NO SPEND. See the header for
  # what makes it possible and for the one rule it is under.
  #
  # `prompt_stable` IS NOT ANSWERED HERE and must not be: it is the claim that
  # every REPETITION of a case sent the same prompt, which is a fact about a run
  # rather than about the tree. One assembly of one prompt cannot say anything
  # about it, and reporting `true` would be reporting a check that was never
  # made.
  #
  # EACH CASE IN ITS OWN ROLLED-BACK COPY OF ITS WORLD, exactly as a pass does
  # it -- the staging is what makes the prompt the app's rather than this file's,
  # and a shared copy would let one case's surgery reach another's.
  def offline(corpus = Eval::Realization.corpus)
    sent = {}
    instructions = []

    designated_cases(corpus).each do |shape, kase|
      Eval::Realization::Stage.open([ kase ]) do |stages|
        generator = stages.fetch(kase.id).generator
        sent[shape] = scrub(built(generator).join("\n \n"))
        instructions << generator.system_prompt
      end
    end

    { prompt_digest: digest(sent.map { |shape, one| "#{shape}\n#{one}" }),
      prompt_shapes: sent.transform_values { |one| Playthrough::PromptVersion.of(one) },
      instructions_digest: digest(instructions.uniq.sort) }
  end

  # ONE CASE PER SHAPE, THE SAME ONE `#designated` PICKS: the lowest case id of
  # that shape. Asked of the CORPUS rather than of readings, because there are
  # no readings without a run.
  def designated_cases(corpus)
    corpus.cases.reject { |kase| kase.staging.present? }.group_by { |kase| kase.shape.to_s }
          .transform_values { |scoped| scoped.min_by(&:id) }.sort.to_h
  end

  # THE PROMPTS ONE CASE WOULD SEND, in the app's own call order. TWO SHAPES OF
  # ROOM SEND ONE PROMPT AND NOT TWO, and assembling a second for either would
  # digest a prompt the app never builds:
  #
  #   A ROOM INSIDE A LAID-OUT PLACE. Its ways out are the engine's, so
  #   `Location::Generator#write_exits!` asks for none -- asked here through the
  #   generator's own `#interior_room?`, so there is no second reading of it.
  #
  #   A BUILDING. Its ways out are its ROOMS' ways out, and it has none of its
  #   own by the time the exits call would be made -- realizing it is what lays
  #   the inside out and moves every doorway onto the entry room, and
  #   `#write_exits!` sees a laid-out place and returns. It cannot be asked
  #   through the same predicate the app uses, because at THIS moment the inside
  #   does not exist yet: the gate is what the detail call is about to do.
  def built(generator)
    return [ generator.detail_prompt ] if generator.interior_room? || generator.location.place?

    [ generator.detail_prompt, generator.exits_prompt ]
  end

  # ONE CASE PER SHAPE, AND THE SAME ONE EVERY RUN: the lowest case id of that
  # shape that actually produced prompts. Chosen by id rather than by position
  # in the file so that reordering the corpus does not silently change the
  # version. Both calls' prompts are joined, in the order the app sends them.
  def designated(readings)
    readings.reject { |reading| reading.prompts.blank? || reading.kase.staging.present? }
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
