# A PLAYTHROUGH'S COPY THAT LAGS THE WORLD'S OWN ROW, and the one writer that
# brings it forward.
#
# THE BUG IT IS FOR. A world outlives its seed file exactly as it outlives its
# schema. The captain seeded The Salt Assizes one evening; the next morning a PR
# edited `db/seeds/worlds/the-salt-assizes.yml` to give the tide-slate
# `readable: true` and an inscription -- and nothing he ran after pulling looked
# at seed files, so the world's own row stayed blank. `bin/update` re-seeds now
# when a seed file moved in the pulled range, which fixes the TEMPLATE. It does
# not fix the COPIES: `Item::Snapshot` copied the blank row into every game
# before the file changed, and the layer split means a re-seed deliberately
# never reaches into a game in progress. So a player whose game predates the
# edit goes on reading a slate with nothing written on it.
#
# WHAT LAGS AND WHAT MERELY DIFFERS. Only `FROM_THE_TEMPLATE` -- what the world
# says the thing IS. Where a thing is and whose hands it is in are the player's
# business and a re-seed must never touch them; `Item::NOT_COPIED` draws that
# line for the snapshot and this draws the same one from the other side.
#
# UNTOUCHED, DEFINED CONSERVATIVELY FROM WHAT THE RECORDS CAN PROVE. Nothing on
# an `items` row says what its template said the day it was copied, so "the
# player edited this" is not a question the records can answer directly. What
# they can answer is whether a turn ever ACTED on the row: `scenes.acted_on` has
# named every take and drop since PR 105. So a copy is untouched when NO scene
# in the story acted on it -- which also covers the only two ways a copy moves,
# since `Playthrough::Turn#carry!` and `#put_down!` both write that column. A
# copy a turn has acted on is REPORTED and left exactly as it stands, because
# the safe answer for a row somebody has handled is to say so and stop.
#
# Offline, deterministic, free: every value it writes is already on a row in the
# same table. No model call, no network.
class Item::TemplateRefresh
  # THE COLUMNS A COPY TAKES FROM ITS TEMPLATE. What the world says the thing IS
  # and nothing else -- `readable` and `inscription` are one fact read from two
  # sides (`Item#inscription_requires_readable`) so they move together or the
  # record refuses them, `description` is the sentence the room's realization
  # wrote, and `bulk` is how hard the world says it is to shift. Deliberately
  # NOT `name`: a rename is what `WorldSeed::Loader` reconciles in the world
  # layer, and following it here would rename a thing in somebody's hands
  # mid-game.
  #
  # `bulk` IS HERE FOR THE REASON THE OTHER THREE ARE, and it is why the column
  # needs no backfill step of its own: a file that gives the tide-slate
  # `bulk: heavy` is the world deciding what the slate weighs, and a copy made
  # before that edit is carrying the default rather than the decision. It is
  # NOT one of `Item::NOT_COPIED` -- where a thing is is the player's, what it
  # weighs is the world's -- so the two lists stay each other's complement.
  FROM_THE_TEMPLATE = %w[readable inscription description bulk].freeze

  # One copy that lags, and by which columns. `touched` is what makes it a
  # report rather than a repair.
  Lag = Data.define(:copy, :template, :columns, :touched) do
    def touched? = touched

    def playthrough_id = copy.playthrough_id

    # `slate: inscription, readable` -- the row and what is behind on it.
    def to_s = "#{copy.name} (playthrough ##{playthrough_id}): #{columns.join(", ")}"
  end

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # EVERY LAGGING COPY IN THE STORY, touched and untouched together, ordered by
  # id so two runs report in the same order.
  def lags
    @lags ||= begin
      copies = Item.in_story(story).instances.where.not(template_id: nil).order(:id).to_a
      templates = Item.in_story(story).templates.index_by(&:id)

      copies.filter_map do |copy|
        template = templates[copy.template_id]
        next if template.nil?

        columns = FROM_THE_TEMPLATE.select { |column| copy[column] != template[column] }
        next if columns.empty?

        Lag.new(copy: copy, template: template, columns: columns, touched: acted_on.include?(copy.id))
      end
    end
  end

  def untouched = lags.reject(&:touched?)

  def touched = lags.select(&:touched?)

  # BRING THE UNTOUCHED ONES FORWARD, and only those. `dry_run` answers what it
  # would write without writing it, which is what `Story::Doctor` asks so the
  # report and the repair cannot disagree.
  #
  # `only:` narrows to one playthrough, because the finding is raised per game.
  def refresh!(dry_run: false, only: nil)
    wanted = untouched
    wanted = wanted.select { |lag| lag.playthrough_id == only.id } if only
    return wanted if dry_run

    Item.transaction do
      wanted.each { |lag| lag.copy.update!(**lag.template.attributes.slice(*lag.columns).symbolize_keys) }
    end

    wanted
  end

  private

  # THE COPY IDS SOME TURN HAS ACTED ON. One query for the story rather than one
  # per row: `scenes(acted_on_type, acted_on_id)` is indexed for exactly this.
  def acted_on
    @acted_on ||= story.scenes.where(acted_on_type: "Item").distinct.pluck(:acted_on_id).compact.to_set
  end
end
