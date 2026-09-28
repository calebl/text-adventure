# THE PEOPLE IN A ROOM REACTING TO THE PARTY'S ARRIVAL, TOLD BY THE ARRIVAL:
# the reactions corpus's cases.
#
# The engine lets each person in the room the party walks into make one choice
# before the arrival is written -- a word on the speech die, or, for whoever
# stays silent, an act -- and tells the arrival writer what they did in an
# "## As You Come In" block after the records. No arrival instruction changed
# for it, so what this measures is whether the prose renders each reaction and
# adds nobody and nothing else: the owner's plan says a line is added to the
# instructions only if these cases show one.
#
# THE SAME STAGED ARRIVAL AS THE ARRIVAL BENCH'S (`Eval::Arrival::Stage`), with
# the rows the dice would have written held on it (`Stage`), with the engine's
# own facts, and the arrival request the engine builds naming them. Its own
# corpus file and its own set, so the arrival bench keeps its kept set.
module Eval::Arrival::Reactions
  CORPUS = Rails.root.join("test/fixtures/files/arrival_reactions_corpus.json")
  BASELINE = Rails.root.join("db/eval/arrival-reactions-2026-09-28")

  def self.cases = JSON.parse(CORPUS.read).fetch("cases")
  def self.model = Eval::Arrival.model
  def self.digest = Digest::SHA256.hexdigest(CORPUS.read)
  def self.stage = Stage

  def self.estimate(reps: Eval::Noise::MIN_RUNS) = Eval::Arrival.estimate(reps: reps, cases: cases)
end
