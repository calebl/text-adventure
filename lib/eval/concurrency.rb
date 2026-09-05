# RUNNING AN EVALUATION'S CALLS AT THE SAME TIME, AND THE ONE DATABASE SHAPE
# THAT MAKES IT SAFE.
#
# WHY IT IS HERE AND NOT IN THE BENCH. 98% of a classifier bench pass is the
# model round trip -- measured, `ta-bench-parallel-scout` §1: 185 of 192 seconds
# of a 300-line pass are spent waiting on OpenRouter, and everything else
# together (the seed loads, the `Chat` and `Message` writes, the closed-set
# queries, the schema build) is under seven. So the pass is network-bound, the
# speedup from N calls in flight is very nearly N, and the only question left is
# what happens to the database underneath it. The PROSE bench being built beside
# this one has exactly the same shape and exactly the same question, and two
# copies of the answer would be two chances to lose it -- so the answer lives
# here and both benches call it.
#
# THE ANSWER IS A PINNED CONNECTION, AND IT IS NOT LUCK. `pin_connection!(true)`
# sets the adapter's `lock_thread`, which installs an
# `ActiveSupport::Concurrency::ThreadMonitor`: every statement, and every
# savepoint a `create!` opens, runs inside one process-wide mutex. So the
# DATABASE work is serialised across the workers -- which is what one SQLite
# handle and one shared transaction stack need -- and it costs nothing, because
# database work is 3.6% of the pass. The HTTP round trip is outside that lock
# and runs fully concurrent. Measured at N=8 with real calls: 813 calls a
# minute, zero failures, and the transaction rolled back leaving the row counts
# exactly as it found them.
#
# AND IT IS A REPLACEMENT FOR `ActiveRecord::Base.transaction`, NEVER A WRAPPER
# AROUND ONE. `TransactionManager#within_new_transaction` holds the connection
# lock for the WHOLE duration of its block, so a `transaction do ... end` with
# worker threads inside it deadlocks on the first statement any worker makes --
# reproducibly, immediately, and with a thread dump that says so. `pin_connection!`
# begins its transaction and returns, holding nothing.
#
# HOW MANY AT ONCE: see `ADVISED_MAX`. The number is a property of the call
# shape and the provider, not of this file, so a bench that measures a different
# kind of call re-measures the curve rather than inheriting the default.
module Eval::Concurrency
  # EIGHT, AND THE REASON IS THE LATENCY AND NOT THE THROUGHPUT. Measured on
  # `mistralai/mistral-medium-3.1` (`ta-bench-parallel-scout` §1):
  #
  #   in flight   throughput   speedup   median latency
  #   1              103.6/min   1.00x   0.541s
  #   4              418.1/min   4.04x   0.538s
  #   8              745.4/min   7.20x   0.565s   (+4%)
  #   16            1095.0/min  10.57x   0.651s   (+20%)
  #   32             981.0/min   9.47x   1.453s   (+169%), for LESS throughput
  #
  # Past about sixteen the provider stops answering faster and starts QUEUEING,
  # and a queued call's wall clock is queueing time reported as model speed.
  # Eight is the last point where the latency the bench prints is still a figure
  # about the model. Above it the run still works and the accuracy figures are
  # unaffected -- it is the two latency columns that stop meaning what they say,
  # which is what `#advice` warns about rather than refusing.
  DEFAULT = 8
  ADVISED_MAX = 8

  # THE ENVIRONMENT'S NUMBER, spelled the way `EvalTasks#concurrency` spells it
  # so one variable means one thing across the whole evaluation module.
  def self.requested(default: DEFAULT, env: ENV)
    value = env["CONCURRENCY"].presence
    [ (value || default).to_i, 1 ].max
  end

  # SAID OUT LOUD WHEN SOMEBODY TYPES A BIG NUMBER, because `CONCURRENCY=32`
  # produces a set whose accuracies are fine and whose latencies are a 169% lie,
  # and nothing in the file itself would say so. nil when there is nothing to
  # warn about.
  def self.advice(threads)
    return nil if threads.to_i <= ADVISED_MAX

    "CONCURRENCY=#{threads.to_i} is above the measured honest ceiling of #{ADVISED_MAX}: past it the " \
      "provider queues, and the latency columns become queueing time rather than model speed. " \
      "The accuracy figures are unaffected. See EVALUATION.md -> Concurrency."
  end

  # EVERY WORKER ON ONE CONNECTION, INSIDE ONE TRANSACTION, ROLLED BACK.
  # RETURNS WHAT THE BLOCK RETURNED.
  #
  # THE ROLLBACK IS IN AN `ensure` AND THAT IS CORRECT HERE, which is worth
  # saying because the shape this replaced could not do it: an `ensure` raising
  # `ActiveRecord::Rollback` REPLACES an exception already in flight, so a
  # failure inside the block would come back as a silent nil.
  # `unpin_connection!` does not raise `ActiveRecord::Rollback` and does not
  # raise at all -- it calls `rollback_transaction` on the connection directly
  # (`connection_pool.rb`, `#unpin_connection!`) -- so it cannot stand in front
  # of a real error on its way out. Do not "fix" this back to a rollback as the
  # last statement of the block: that shape holds the connection lock for the
  # length of the block and deadlocks every worker.
  #
  # REENTRANT, which is what lets the tests that assert this run inside Rails'
  # own transactional fixtures: the pool counts the depth and the inner pin is a
  # savepoint.
  def self.rolled_back
    pool = ActiveRecord::Base.connection_pool
    pool.pin_connection!(true)

    begin
      yield
    ensure
      pool.unpin_connection!
    end
  end

  # WORK HANDED OUT OFF A QUEUE AND WRITTEN BACK BY INDEX. The index is the
  # whole of it: appending as answers arrive would put the corpus in completion
  # order and silently mis-attribute every reading to the wrong line, which is a
  # bug that produces plausible numbers and no error.
  #
  # An exception in the block travels out through `Thread#join`, so a caller
  # that wants a failure counted rather than raised rescues it in the block --
  # which is what `Eval::Classifier::Bench#read` already does.
  def self.fan(items, threads:)
    rows = items.to_a
    workers = [ threads.to_i, 1 ].max
    return rows.map { |item| yield item } if workers == 1 || rows.size <= 1

    answers = Array.new(rows.size)
    queue = Queue.new
    rows.each_index { |index| queue << index }
    [ workers, rows.size ].min.times { queue << nil }

    pool = Array.new([ workers, rows.size ].min) do
      Thread.new do
        while (index = queue.pop)
          answers[index] = yield rows[index]
        end
      end
    end

    pool.each(&:join)
    answers
  end
end
