# WHAT A PURSUIT LABEL DOES, AND IT IS A TABLE IN CODE.
#
# `characters.desire_pursuit` is one of seven words a model picked
# (`Character::PURSUITS`). This is the whole of what the engine does with that
# word: it reads a column of this table and weights a die with it. A model
# answering `obtain` has not told the engine to pick anything up -- it has told
# the engine which row to read, and the row is here, beside its tests, where a
# person changed it on purpose.
#
# THAT IS THE PROJECT'S RULE THAT A WORLD SUPPLIES PARAMETERS AND NEVER
# BEHAVIOUR, applied to a person. It is the same shape `Location::Danger` gives
# a room's `danger` word and `Location::Population` gives its `population`
# word: a closed vocabulary outside, arithmetic inside.
#
# THE WEIGHTS ARE ON TOKEN SHAPES AND NOT ON TOKENS. A turn offers
# `move:412`, `move:418`, `take:77`; this table knows only `move` and `take`,
# and every token of a shape shares that shape's weight. So a room with three
# ways out is three times as likely to be walked out of as a room with one,
# which is the right answer and is the answer a table keyed on whole tokens
# could not give.
#
# EVERY OFFERED TOKEN KEEPS A FLOOR (`BASE`), so nothing the engine put in
# front of somebody is impossible. A weight of nought in a row below means
# "only as likely as anything else", never "never".
#
# NOBODY IS WEIGHTED BY `need_pursuit` IN THIS SLICE, and that is a deliberate
# stopping point rather than an oversight. The article's meta-conflict -- they
# want to be different and will not change -- is the CONSCIOUS pursuit winning
# by default and the need's weights taking over only once a condition the
# engine checks holds. The condition is a count over `playthrough_volitions`,
# the table this slice creates and does not yet read. Until there is something
# to count, weighting by the need would be the second half of a mechanism
# whose first half has not run.
module Playthrough::Volition::Weights
  # THE SHAPES A TOKEN CAN HAVE. `Playthrough::Volition` builds the tokens; this
  # is the vocabulary they are weighted in, and the two lists have to agree --
  # `Playthrough::VolitionTest` asserts that every shape a turn can offer has a
  # column here.
  SHAPES = %w[wait move take give follow stop_following].freeze

  # THE FLOOR UNDER EVERY OFFERED TOKEN. Small enough that a pursuit's own
  # weights decide the ordinary case, large enough that no token the engine
  # offered is unreachable.
  BASE = 1

  # WHAT EACH PURSUIT PULLS TOWARD, in weight added on top of `BASE`.
  #
  # Read a row as a sentence about somebody: `reach` walks, `obtain` picks
  # things up, `offer` puts them into hands, `attend` stays where the player
  # is, `avoid` leaves, `keep` and `withhold` stand over what they have and do
  # not hand it over.
  #
  # `give` IS NOUGHT FOR `keep` AND `withhold` ON PURPOSE. Those two are the
  # rows whose whole content is not letting go, so they are left on the floor
  # rather than pushed below it -- a character who will not hand the ledger
  # over is a character for whom handing it over is merely unlikely, and an
  # impossible act is not a reluctance, it is a rule the engine would be
  # enforcing on somebody's behalf.
  TABLE = {
    "keep" => { "wait" => 6, "move" => 1, "take" => 2, "give" => 0, "follow" => 1, "stop_following" => 3 },
    "obtain" => { "wait" => 2, "move" => 3, "take" => 8, "give" => 0, "follow" => 2, "stop_following" => 1 },
    "reach" => { "wait" => 1, "move" => 8, "take" => 1, "give" => 0, "follow" => 1, "stop_following" => 2 },
    "attend" => { "wait" => 5, "move" => 1, "take" => 1, "give" => 1, "follow" => 8, "stop_following" => 0 },
    "avoid" => { "wait" => 1, "move" => 8, "take" => 0, "give" => 1, "follow" => 0, "stop_following" => 3 },
    "withhold" => { "wait" => 6, "move" => 2, "take" => 6, "give" => 0, "follow" => 1, "stop_following" => 2 },
    "offer" => { "wait" => 2, "move" => 2, "take" => 1, "give" => 9, "follow" => 3, "stop_following" => 0 }
  }.freeze

  # AND SOMEBODY THE WORLD HAS NOT SAID ANYTHING ABOUT DOES NOTHING AT ALL.
  #
  # `#row_for` answers nil for them and `Playthrough::Volition` gives them no
  # turn -- no roll, no row, no fact. This is the load-bearing half of the
  # whole feature and it is worth being blunt about why it is a hard nothing
  # rather than a small chance of something.
  #
  # A WORLD SUPPLIES PARAMETERS AND NEVER BEHAVIOUR is the project's rule, and
  # the honest reading of it is that where there is no parameter there is no
  # behaviour. A person the world has stated no goal for is a person the engine
  # has no reason to move, and inventing a reason would be the engine supplying
  # the behaviour itself.
  #
  # AND IT IS WHAT MAKES THIS SAFE TO SHIP WITHOUT A BACKFILL. Every character
  # written before the desire columns existed, and everybody a world file
  # leaves without a pursuit, behaves exactly as they did yesterday: inert
  # until somebody is typed at. A small chance of something would instead have
  # every un-backfilled world's cast start wandering off on the first turn of
  # the first game anybody played after the migration -- a change to every
  # stored world, made as a side effect of a migration, that nobody chose.
  # `rake game:doctor` reports who is in this state and
  # `rake game:backfill_desires` is how somebody opts them in.
  def self.row_for(pursuit) = TABLE[pursuit.to_s]

  # WHETHER THE ENGINE HAS ANYTHING TO WEIGHT A DIE WITH. The one question
  # `Playthrough::Volition` asks before it throws one.
  def self.weighted?(pursuit) = !row_for(pursuit).nil?

  # THE WEIGHT OF ONE OFFERED TOKEN under one pursuit. `shape_of` is
  # `Playthrough::Volition`'s, so a token and its weight are read out of one
  # spelling of the token.
  def self.weight_for(token, pursuit:)
    BASE + row_for(pursuit).to_h.fetch(Playthrough::Volition.shape_of(token), 0)
  end

  # ONE TOKEN OUT OF THE OFFERED SET, drawn from the generator it is handed.
  #
  # `Roll` IS THE ONE PLACE A DIE IS THROWN and this is a die: an integer in
  # 1..total, walked down the weights in the order the tokens were offered. The
  # order is the caller's and is fixed (`wait` first, then each shape in
  # `id` order), so the same turn of the same game draws the same token in any
  # process, after any restart, for ever -- which is what lets `rake game:sweep`
  # assert what somebody did without buying anything.
  #
  # NIL FOR AN EMPTY SET, which cannot happen -- `wait` is always offered -- and
  # is answered rather than raised so that a caller holding an empty list does
  # nothing instead of ending a turn.
  def self.pick(tokens, pursuit:, rng:)
    tokens = Array(tokens)
    return nil if tokens.empty? || !weighted?(pursuit)

    weights = tokens.map { |token| weight_for(token, pursuit: pursuit) }
    Roll.weighted_one_of(tokens, weights, rng: rng)
  end
end
