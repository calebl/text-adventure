# THE TWO LABS FROM THE COMMAND LINE, AND THE TWO THINGS EACH IS FOR.
#
#   rake lab:realization:draw KIND=<id> N=<count> YES=1
#   rake lab:realization:promote KIND=<id>
#   rake lab:exits:draw VANTAGE=<id> N=<count> YES=1
#   rake lab:exits:promote VANTAGE=<id>
#
# `promote` IS THE WAY OUT OF EITHER LAB. A kind or a vantage established here is
# one he has an opinion about; `promote` writes it out as an `Eval::Realization`
# corpus case so the next prompt change is measured against that opinion, which
# is the *"maintain alignment in the future"* half of his ask.
# `Lab::Realization::Promotion` and `Lab::Exits::Promotion` are the emitters and
# their headers are why they print text rather than writing the file.
#
# WHY IT EXISTS, in the captain's own terms: *"I want to make sure it is picking
# what I think it should MOST OF THE TIME."* Most of the time is a rate, a rate
# needs a denominator, and `Lab::Realization::MIN_DRAWS` is how many draws before
# one is worth printing as a figure -- which is that many clicks of the draw
# button on `/lab/kinds/:id`. This is the same draws without the clicking, and
# that is its whole contribution: it makes NO decision the page does not make.
#
# THE SAME RUNNER, THE SAME ROWS. `Lab::Realization::Runner#draw!` is what
# `Lab::SamplesController#create` calls, and a sample written here is
# indistinguishable from one written by a click. A second path to a sample would
# be a second answer to what a sample is.
#
# AND `rake game:*` IS NOT WHERE IT LIVES. AGENTS.md's rule -- the rake tasks
# build worlds, the browser plays them -- and this builds neither: it buys
# measurements. `eval:` is the namespace for the instruments a prompt is judged
# with; `lab:` is the namespace for the one a LABEL comes from
# (`Lab::Realization`'s header has the distinction and why it must stay
# tellable).
#
# IT SPENDS MONEY. So it prints the estimate before it starts, refuses without a
# key, refuses in the test environment and refuses without `YES=1` -- which is
# `RealizationTasks#run!`'s gate with one difference, stated in `LabTasks`.
namespace :lab do
  namespace :realization do
    desc "Draw one kind N times through the lab's own runner. Usage: rake lab:realization:draw KIND=<id> N=10 YES=1"
    task draw: :environment do
      LabTasks.draw!
    end

    desc "Every kind in the lab, with its id and how many samples it has -- offline, free"
    task kinds: :environment do
      LabTasks.list!
    end

    desc "A scored kind, written out as a realization corpus case for you to read and commit -- " \
         "offline, no model call, no key. Usage: rake lab:realization:promote KIND=<id>"
    task promote: :environment do
      LabTasks.promote!
    end
  end

  # THE EXITS LAB'S TWO, and it is the realization lab's draw command with one
  # subject swapped -- every gate, every price and every refusal below is
  # `LabTasks`' own, because a draw for this lab IS a draw for that one read from
  # the other end (`Lab::Exits::Runner`).
  #
  # AND `promote` IS HERE NOW, which is the captain's Call 6 of 2026-09-08:
  # a scored vantage becomes an `Eval::Realization` corpus case carrying its
  # `absent` list and its quantifier. It prints and never writes, for
  # `Lab::Exits::Promotion`'s reason -- committing a case moves
  # `Eval::Realization.digest` and puts the tree out of baseline until a set is
  # bought, which is a spend decision and therefore a person's.
  namespace :exits do
    desc "Draw one vantage N times through the exits lab's own runner. " \
         "Usage: rake lab:exits:draw VANTAGE=<id> N=10 YES=1"
    task draw: :environment do
      LabTasks.draw_vantage!
    end

    desc "Every vantage in the exits lab, with its id and how many draws it has -- offline, free"
    task vantages: :environment do
      LabTasks.list_vantages!
    end

    desc "A scored vantage, written out as a realization corpus case for you to read and commit -- " \
         "offline, no model call, no key. Usage: rake lab:exits:promote VANTAGE=<id>"
    task promote: :environment do
      LabTasks.promote_vantage!
    end
  end
end

# The lab's rake half. Separate from `eval.rake`'s three modules for
# `RealizationTasks`' own reason: it measures a different thing over a different
# corpus -- a kind the captain typed rather than a checked-in case -- and shares
# only the arm selector and the pricing, both of which it borrows rather than
# respells.
module LabTasks
  extend self

  # WHAT THIS TASK WILL SPEND UNATTENDED WITHOUT BEING TOLD TWICE. Lower than
  # `RealizationTasks::SPEND_CEILING` because the two knobs are different: the
  # bench's spend is bounded by a corpus that is checked in, and this one's is
  # bounded by a number a person types -- `N=300` is one keystroke from `N=30`.
  SPEND_CEILING = 0.25

  # AND `YES=1` IS REQUIRED WHETHER OR NOT THE CEILING IS CROSSED, which is the
  # one place this departs from `RealizationTasks#run!`. There, a run under the
  # ceiling is the ordinary case and the corpus is fixed, so an unattended run is
  # a known quantity; here every run is a purchase of a size the caller chose, and
  # a task that spends on the strength of two environment variables is a task that
  # spends on a typo.
  CONFIRMATION = "YES".freeze

  def draw!
    kind = kind_or_abort
    count = count_or_abort
    arm = Eval::Classifier::Arm.all([ BaseAgent::REMOTE_MODEL_IDS.first ]).first

    # THE PRICE, THEN THE CONFIRMATION, THEN WHETHER IT COULD RUN AT ALL. That
    # order is deliberate: a caller who has not said `YES=1` should be told the
    # price and asked, not told about a missing key -- the missing key is only
    # interesting to somebody who has already decided to spend.
    estimate!(kind, count, arm)
    refuse_without_confirmation
    refuse_without_a_key(arm)

    puts "Drawing #{kind.name.inspect} in #{kind.world} #{count} #{"time".pluralize(count)} on #{arm.id}."
    puts
    drawn = run_draws(kind, count, arm)
    report(kind, drawn, arm)
  end

  # THE EXITS LAB'S DRAW, and it is `#draw!` with one subject swapped. Every gate
  # is shared and none is re-argued: the price first, then `YES=1`, then whether
  # there is a key at all.
  #
  # PRICED AT BOTH CALLS, ALWAYS, which is the one thing simpler here than for a
  # kind. A vantage cannot be a building -- `Lab::Exits::Vantage`'s header says
  # why it is unreachable rather than refused -- so `#write_exits!` always asks,
  # and there is no cheaper one-call draw to model.
  def draw_vantage!
    vantage = vantage_or_abort
    count = count_or_abort
    arm = Eval::Classifier::Arm.all([ BaseAgent::REMOTE_MODEL_IDS.first ]).first

    estimate_vantage!(count, arm)
    refuse_without_confirmation
    refuse_without_a_key(arm)

    puts "Drawing the ways out of #{vantage.name.inspect} in #{vantage.world} " \
         "#{count} #{"time".pluralize(count)} on #{arm.id}."
    puts vantage.absent_names.any? ?
      "Off the books first: #{vantage.absent_names.join(", ")}." :
      "NOTHING is off the books, so every pick about a place this world already holds will be discarded."
    puts
    drawn = run_vantage_draws(vantage, count, arm)
    report_vantage(vantage, drawn, arm)
  end

  def list_vantages!
    vantages = Lab::Exits::Vantage.order(:id)
    if vantages.empty?
      puts "No vantages yet. The exits lab is at /lab/exits -- a vantage is typed there, not here."
      return
    end

    vantages.each do |vantage|
      rate = vantage.hit_rate
      puts format("  %4d  %-28s %-24s %2d draw%s, %2d distinct, %s off the books",
                  vantage.id, vantage.name, vantage.world, rate.drawn,
                  rate.drawn == 1 ? "" : "s", rate.distinct_answers,
                  vantage.absent_names.size.zero? ? "nothing" : vantage.absent_names.size.to_s)
    end
  end

  def list!
    kinds = Lab::Realization::Kind.order(:id)
    if kinds.empty?
      puts "No kinds yet. The lab is at /lab/kinds -- a kind is typed there, not here."
      return
    end

    kinds.each do |kind|
      puts format("  %4d  %-28s %-28s %d sample%s", kind.id, kind.name, kind.world,
                  kind.samples.count, kind.samples.count == 1 ? "" : "s")
    end
  end

  # A KIND, AS A CORPUS CASE, PRINTED. It writes nothing:
  # `test/fixtures/files/realization_corpus.yml` is a checked-in measurement
  # input, so committing a case moves `Eval::Realization.digest` and puts the
  # tree out of baseline until a new set is bought -- which is a spend decision
  # and therefore a person's. `Lab::Realization::Promotion`'s header is the
  # argument in full.
  #
  # FREE, AND IT IS THE ONE COMMAND IN THIS FILE THAT IS. `draw!` above buys
  # calls; this reads rows already bought.
  def promote!
    kind = kind_or_abort(verb: "promote")
    promotion = Lab::Realization::Promotion.new(kind)

    puts preamble(kind)
    puts
    puts promotion.to_yaml
  end

  # A VANTAGE, AS A CORPUS CASE, PRINTED -- `#promote!`'s contract with one
  # subject swapped, and it writes nothing for the same reason: the corpus is a
  # checked-in measurement input, so committing a case is a spend decision.
  #
  # FREE. `draw_vantage!` above buys calls; this reads draws already bought.
  def promote_vantage!
    vantage = vantage_or_abort(verb: "promote")
    promotion = Lab::Exits::Promotion.new(vantage)

    puts vantage_preamble(vantage)
    puts
    puts promotion.to_yaml
  end

  private

  # WHAT THE PERSON PASTING IT HAS TO KNOW, printed above the case rather than
  # left in a file header they have no reason to open.
  def preamble(kind)
    <<~TEXT.rstrip
      # #{kind}: #{kind.samples.count} drawn, #{kind.hit_rate.judged} judged.
      #
      # PASTE THIS UNDER `cases:` IN test/fixtures/files/realization_corpus.yml YOURSELF.
      # This task prints and never writes: every case in that file is folded into
      # `Eval::Realization.digest`, so committing one moves the corpus digest, and a
      # moved digest fails `Eval::Realization::KeptSetTest` until a new baseline set
      # is bought and `Eval::Realization::BASELINE` points at it. That is a spend
      # decision and it is the captain's, so the last step is a person reading a diff.
      #
      # Then, before you commit: `bin/rails test test/lib/eval/realization/corpus_test.rb`
      # is the offline validator, and `rake eval:realization_digest` prints where the
      # digest landed.
    TEXT
  end

  # AND THE SAME FOR A VANTAGE, with the two things a promoted vantage adds to
  # the warning: its `absent` list travels with it, and its SHAPE is new -- so
  # the first one committed moves the prompt digest as well as the corpus digest
  # (`Lab::Exits::Promotion::SHAPE`).
  def vantage_preamble(vantage)
    rate = vantage.hit_rate
    <<~TEXT.rstrip
      # #{vantage}: #{rate.drawn} drawn, #{rate.distinct_answers} distinct, #{rate.judged} judged,
      # #{vantage.absent_names.size} off the books.
      #
      # PASTE THIS UNDER `cases:` IN test/fixtures/files/realization_corpus.yml YOURSELF.
      # This task prints and never writes: every case in that file is folded into
      # `Eval::Realization.digest`, so committing one moves the corpus digest, and a
      # moved digest fails `Eval::Realization::KeptSetTest` until a new baseline set
      # is bought and `Eval::Realization::BASELINE` points at it. That is a spend
      # decision and it is the captain's, so the last step is a person reading a diff.
      #
      # AND `#{Lab::Exits::Promotion::SHAPE}` IS A SHAPE THE CORPUS DOES NOT HOLD YET, so the
      # first of these committed also becomes a designated case and moves the PROMPT
      # digest (Eval::Realization::Version). Say so in the PR, or the next reader will
      # credit that movement to a prompt nobody touched.
      #
      # Then, before you commit: `bin/rails test test/lib/eval/realization/corpus_test.rb`
      # is the offline validator, and `rake eval:realization_digest` prints where the
      # digest landed.
    TEXT
  end

  # THE KIND, BY THE ID THE PAGE PRINTS. A missing or unknown `KIND` is a
  # person's mistake and gets a sentence naming the way to find the right one --
  # never a stack trace, and never a guess at which kind was meant.
  def kind_or_abort(verb: "draw")
    id = ENV["KIND"].presence or
      abort "KIND=<id> is the kind to #{verb}. `rake lab:realization:kinds` lists them, and the lab " \
            "at /lab/kinds is where one is typed."

    Lab::Realization::Kind.find_by(id: id) or
      abort "There is no kind #{id.inspect}. `rake lab:realization:kinds` lists the ones there are."
  end

  # THE VANTAGE, BY THE ID THE PAGE PRINTS -- `#kind_or_abort`'s shape and its
  # reason: a missing or unknown id is a person's mistake and gets a sentence
  # naming the way to find the right one.
  def vantage_or_abort(verb: "draw")
    id = ENV["VANTAGE"].presence or
      abort "VANTAGE=<id> is the vantage to #{verb}. `rake lab:exits:vantages` lists them, and the lab " \
            "at /lab/exits is where one is typed."

    Lab::Exits::Vantage.find_by(id: id) or
      abort "There is no vantage #{id.inspect}. `rake lab:exits:vantages` lists the ones there are."
  end

  # HOW MANY. Required rather than defaulted, because a default would be this
  # file deciding how much of his money to spend; and a whole number above zero,
  # because `N=0` is a request to spend nothing that would print a rate over an
  # empty denominator.
  def count_or_abort
    given = ENV["N"].presence or
      abort "N=<count> is how many draws. #{Lab::Realization::MIN_DRAWS} is what " \
            "Lab::Realization::MIN_DRAWS calls established."

    count = given.to_i
    abort "N=#{given.inspect} is not a count. It wants a whole number above zero." unless count.positive?

    count
  end

  # THE PRICE FIRST, ALWAYS, AND MEASURED RATHER THAN MODELLED -- the same
  # `Eval::Realization::PER_CALL` figures `rake eval:estimate` quotes and the
  # same `Eval::Cost` registry, so the two commands cannot quote different prices
  # for the same call.
  #
  # PRICED PER CALL RATHER THAN THROUGH `Eval::Realization.estimate`, which is
  # the one arithmetic this file does for itself and the reason is a real
  # difference: that method prices a case at BOTH calls, and a building makes
  # only the detail call (`Location::Generator#write_exits!` returns early once
  # the way in has been moved onto a room). Pricing a building as a room would
  # overstate the dearer of the two calls on every draw.
  def estimate!(kind, count, arm)
    calls = kind.place? ? [ Eval::Realization::CALLS.first ] : Eval::Realization::CALLS
    priced = arm.price.of(count * calls.sum { |call| Eval::Realization::PER_CALL.fetch(call)[:input] },
                          count * calls.sum { |call| Eval::Realization::PER_CALL.fetch(call)[:output] })

    puts format("ESTIMATE: %d call%s (%d draw%s x %s) on %s, about $%.4f.",
                count * calls.size, (count * calls.size) == 1 ? "" : "s",
                count, count == 1 ? "" : "s", calls.join(" + "), arm.id, priced)
    puts format("A sample is a %s, so it is %s. Measured at %d in / %d out a detail call and " \
                "%d in / %d out an exits call (Eval::Realization::PER_CALL).",
                kind.place? ? "building" : "room",
                kind.place? ? "the detail call alone" : "both calls",
                Eval::Realization::PER_CALL["detail"][:input], Eval::Realization::PER_CALL["detail"][:output],
                Eval::Realization::PER_CALL["exits"][:input], Eval::Realization::PER_CALL["exits"][:output])
    abort "That is over the $#{format("%.2f", SPEND_CEILING)} this task will spend at all. Lower N." if
      priced > SPEND_CEILING
  end

  # BOTH CALLS, EVERY TIME -- see `#draw_vantage!`. Otherwise it is `#estimate!`'s
  # arithmetic on the same `Eval::Realization::PER_CALL` figures and the same
  # `Eval::Cost` registry, so the two commands cannot quote different prices for
  # the same call.
  def estimate_vantage!(count, arm)
    calls = Eval::Realization::CALLS
    priced = arm.price.of(count * calls.sum { |call| Eval::Realization::PER_CALL.fetch(call)[:input] },
                          count * calls.sum { |call| Eval::Realization::PER_CALL.fetch(call)[:output] })

    puts format("ESTIMATE: %d calls (%d draw%s x %s) on %s, about $%.4f.",
                count * calls.size, count, count == 1 ? "" : "s", calls.join(" + "), arm.id, priced)
    puts format("A vantage is never a building, so it is always both calls. Measured at %d in / %d out " \
                "a detail call and %d in / %d out an exits call (Eval::Realization::PER_CALL).",
                Eval::Realization::PER_CALL["detail"][:input], Eval::Realization::PER_CALL["detail"][:output],
                Eval::Realization::PER_CALL["exits"][:input], Eval::Realization::PER_CALL["exits"][:output])
    abort "That is over the $#{format("%.2f", SPEND_CEILING)} this task will spend at all. Lower N." if
      priced > SPEND_CEILING
  end

  # THE DRAWS, ONE TRANSACTION EACH, A RUNNING TOTAL AFTER EVERY ONE --
  # `#run_draws`' contract and its reason: an interrupted run leaves every sample
  # it already bought and has still said what it spent.
  def run_vantage_draws(vantage, count, arm)
    spent = 0.0

    (1..count).map do |draw|
      sample = Lab::Exits::Runner.new(vantage, arm: arm.id).draw!
      spent += cost_of(sample, arm)
      puts format("  %3d/%-3d  draw #%-6d %-52s $%.4f so far",
                  draw, count, sample.id, vantage_headline(sample), spent)
      sample
    rescue Eval::Realization::Stage::Unstageable => error
      abort "  #{error.message}"
    end
  end

  # WHAT ONE DRAW SAID, AS ONE LINE, and it is the two numbers this lab is about:
  # how many places were named and how many of the bands given actually opened
  # one. A draw whose second number is nought bought nothing measurable.
  def vantage_headline(sample)
    return "FAILED: #{sample.reading.error_class}" if sample.failed?
    return "named nothing" unless sample.answered?

    format("%d named, %d inside%s given, %d reaching", sample.named_places.size,
           sample.insides_given.size, sample.insides_given.size == 1 ? "" : "s",
           sample.insides_reaching.size)
  end

  def report_vantage(vantage, drawn, arm)
    spent = drawn.sum { |sample| cost_of(sample, arm) }
    failed = drawn.count(&:failed?)
    reach = vantage.hit_rate.reach

    puts
    puts format("Drew %d, %d failed, $%.4f spent. %s now has %d draw%s.",
                drawn.size, failed, spent, vantage.name, vantage.samples.count,
                vantage.samples.count == 1 ? "" : "s")
    puts format("Over every draw of it: %d place%s named, %d given an inside, %d of those reaching " \
                "the world.", reach.named, reach.named == 1 ? "" : "s", reach.given, reach.reaching)
    puts "Look at them, judge each place and read the rate at /lab/exits/vantages/#{vantage.id}."
  end

  def refuse_without_a_key(arm)
    abort "The lab must not draw in the test environment." if Rails.env.test?
    return if arm.local? || ENV["OPENROUTER_API_KEY"].present?

    abort "OPENROUTER_API_KEY is not set and #{arm.id} is hosted, so there is nothing to draw with. " \
          "AGENTS.md has both ways out."
  end

  def refuse_without_confirmation
    return if ENV[CONFIRMATION] == "1"

    abort "This spends money, so it wants #{CONFIRMATION}=1 as well. Re-run with #{CONFIRMATION}=1."
  end

  # THE DRAWS, ONE TRANSACTION EACH, AND A RUNNING TOTAL AFTER EVERY ONE.
  # `Lab::Realization::Runner` holds one transaction per sample deliberately (the
  # development database has one writer), so an interrupted run leaves every
  # sample it already bought -- and the total is printed as it goes so an
  # interrupted run has still said what it spent.
  #
  # A FAILED CALL IS STILL A SAMPLE and is stored like any other
  # (`Lab::SamplesController#create`'s note). What aborts the run is a kind that
  # cannot be staged at all, which is the same mistake every draw of it would
  # make.
  def run_draws(kind, count, arm)
    spent = 0.0

    (1..count).map do |draw|
      sample = Lab::Realization::Runner.new(kind, arm: arm.id).draw!
      spent += cost_of(sample, arm)
      puts format("  %3d/%-3d  sample #%-6d %-46s $%.4f so far",
                  draw, count, sample.id, headline(sample), spent)
      sample
    rescue Eval::Realization::Stage::Unstageable => error
      abort "  #{error.message}"
    end
  end

  # WHAT ONE DRAW ACTUALLY COST, off the tokens the provider reported on the
  # stored row and priced through `Eval::Cost` -- the same registry
  # `Eval::Realization.estimate` prices with. Not the estimate again: the point
  # of printing it as it goes is that it is the bill and not the quote.
  def cost_of(sample, arm)
    arm.price.of(sample.row["input_tokens"].to_i, sample.row["output_tokens"].to_i)
  end

  def headline(sample)
    return "FAILED: #{sample.reading.error_class}" if sample.failed?

    rooms = sample.reading.rooms
    return sample.reading.name_after.to_s if rooms.empty?

    "#{sample.reading.name_after} -- #{rooms.size} #{"room".pluralize(rooms.size)}"
  end

  # WHAT WAS BOUGHT, AND WHERE TO GO AND LOOK AT IT. The hit rate is
  # `Lab::Realization::HitRate`'s and is printed rather than recomputed, so this
  # task and the kind's page cannot report different rates -- and it says "not
  # established" below `MIN_DRAWS` because that is the one thing an instrument
  # must not dress up.
  def report(kind, drawn, arm)
    spent = drawn.sum { |sample| cost_of(sample, arm) }
    failed = drawn.count(&:failed?)

    puts
    puts format("Drew %d, %d failed, $%.4f spent. %s now has %d sample%s.",
                drawn.size, failed, spent, kind.name, kind.samples.count,
                kind.samples.count == 1 ? "" : "s")
    puts "Look at them, judge them and read the hit rate at /lab/kinds/#{kind.id}."
  end
end
