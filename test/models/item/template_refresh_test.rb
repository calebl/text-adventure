require "test_helper"

# A COPY THAT LAGS THE WORLD'S OWN ROW.
#
# The bug: The Salt Assizes was seeded one evening, the seed file gave the
# tide-slate `readable: true` and an inscription the next morning, and nothing
# the captain ran after pulling looked at seed files. `bin/update` re-seeds now,
# which puts the words on the TEMPLATE -- and, correctly, stops there, because
# re-asserting a file must never reach into a game in progress. This is what
# brings the copies that nobody has touched forward with it.
#
# Offline: every value it writes is on a row in the same table.
class Item::TemplateRefreshTest < ActiveSupport::TestCase
  def setup
    @story = create(:story)
    @protagonist = create(:character, :protagonist, story: @story, fullname: "Odile Vance")
    @office = create(:location, story: @story, name: "Ward Office 12")
    @playthrough = create(:playthrough, story: @story, character: @protagonist, current_location: @office)
  end

  # A template and the copy some earlier snapshot made of it, back when the
  # template said something else. Built directly rather than through
  # `Item::Snapshot`, because the whole point is a copy made BEFORE the edit.
  def lagging_pair(**template_now)
    template = create(:item, :lying, location: @office, name: "assize tide-slate")
    copy = create(:item, :lying, location: @office, playthrough: @playthrough, template: template,
                                 name: template.name, description: template.description)
    template.update!(**template_now) if template_now.any?
    [ template, copy.reload ]
  end

  def refresh = Item::TemplateRefresh.new(@story)

  # --- what counts as lagging ---------------------------------------------

  test "a copy whose text matches its template is not lagging" do
    template = create(:item, :lying, :readable, location: @office)
    create(:item, :lying, location: @office, playthrough: @playthrough, template: template,
                          name: template.name, description: template.description,
                          readable: true, inscription: template.inscription)

    assert_empty refresh.lags
  end

  test "words the world has written since the copy was made are a lag" do
    _template, copy = lagging_pair(readable: true, inscription: "Three hours forty after noon.")

    lag = refresh.lags.sole

    assert_equal copy, lag.copy
    assert_equal %w[readable inscription], lag.columns
    assert_not_predicate lag, :touched?
  end

  test "a description the world rewrote is a lag too" do
    _template, _copy = lagging_pair(description: "A slate of grey stone, the chalk half wiped.")

    assert_equal %w[description], refresh.lags.sole.columns
  end

  # A BULK THE FILE DECIDED SINCE THE COPY WAS MADE IS A LAG, and it is here for
  # the reason the three above it are: what a thing WEIGHS is the world's, and a
  # copy carrying the column's default is carrying the absence of a decision.
  # It is also why `items.bulk` needs no `bin/update` step -- the default covers
  # every existing row and this covers every existing copy.
  test "a bulk the world decided since the copy was made is a lag" do
    _template, copy = lagging_pair(bulk: "heavy")

    lag = refresh.lags.sole

    assert_equal %w[bulk], lag.columns
    assert_equal Item::HANDY, copy.bulk
    refresh.refresh!

    assert_equal "heavy", copy.reload.bulk
  end

  # THE TWO LISTS ARE EACH OTHER'S COMPLEMENT: where a thing is is the player's
  # (`Item::NOT_COPIED`) and what it is is the world's (this).
  test "nothing is in both this list and the one a copy leaves behind" do
    assert_empty Item::TemplateRefresh::FROM_THE_TEMPLATE & Item::NOT_COPIED
  end

  # WHERE A THING IS AND WHOSE HANDS IT IS IN ARE THE PLAYER'S. `Item::Snapshot`
  # draws that line with `Item::NOT_COPIED`; this draws the same one from the
  # other side, so a party carrying a thing the world still calls "lying in the
  # office" is not a lag.
  test "a copy in the party's hands does not lag a template lying in a room" do
    template = create(:item, :lying, location: @office, name: "ward stamp")
    create(:item, playthrough: @playthrough, template: template, character: nil, location: nil,
                  name: template.name, description: template.description)

    assert_empty refresh.lags
  end

  test "a name the world renamed is not a lag -- a rename is the loader's business" do
    template, _copy = lagging_pair
    template.update!(name: "the assize tide-slate")

    assert_empty refresh.lags
  end

  test "a copy of a template that no longer exists is invisible here" do
    template, copy = lagging_pair(readable: true, inscription: "Three hours forty after noon.")
    template.destroy!

    assert_nil copy.reload.template_id
    assert_empty refresh.lags
  end

  # --- touched and untouched ----------------------------------------------

  # `scenes.acted_on` has named every take and drop since PR 105, and
  # `Playthrough::Turn#carry!` / `#put_down!` are the only two writers of a
  # copy's place -- so "no turn acted on this row" is the whole of what the
  # records can prove about a copy nobody has handled.
  test "a copy some turn took is touched, and is left alone" do
    _template, copy = lagging_pair(readable: true, inscription: "Three hours forty after noon.")
    create(:scene, story: @story, location: @office, resolved_action: "take", acted_on: copy)

    assert_predicate refresh.lags.sole, :touched?
    assert_empty refresh.untouched
    assert_equal [ copy ], refresh.touched.map(&:copy)
  end

  test "a turn that acted on the TEMPLATE does not make the copy touched" do
    template, _copy = lagging_pair(readable: true, inscription: "Three hours forty after noon.")
    create(:scene, story: @story, location: @office, resolved_action: "take", acted_on: template)

    assert_not_predicate refresh.lags.sole, :touched?
  end

  # --- what the refresh writes --------------------------------------------

  test "an untouched copy is brought forward, and only its text" do
    template, copy = lagging_pair(readable: true, inscription: "Three hours forty after noon.")

    assert_equal [ copy ], refresh.refresh!.map(&:copy)

    copy.reload
    assert_predicate copy, :readable?
    assert_equal template.inscription, copy.inscription
    assert_equal @office, copy.location
    assert_equal @playthrough, copy.playthrough
    assert_equal template, copy.template
  end

  test "a touched copy is never written, even beside an untouched one" do
    _template, touched = lagging_pair(readable: true, inscription: "Three hours forty after noon.")
    create(:scene, story: @story, location: @office, resolved_action: "take", acted_on: touched)
    _other, untouched = lagging_pair(readable: true, inscription: "Ten past eight.")

    Item::TemplateRefresh.new(@story).refresh!

    assert_not_predicate touched.reload, :readable?
    assert_nil touched.inscription
    assert_predicate untouched.reload, :readable?
  end

  test "a dry run writes nothing and answers what it would write" do
    _template, copy = lagging_pair(readable: true, inscription: "Three hours forty after noon.")

    assert_equal [ copy ], Item::TemplateRefresh.new(@story).refresh!(dry_run: true).map(&:copy)
    assert_not_predicate copy.reload, :readable?
  end

  test "it is idempotent -- a second run has nothing to do" do
    lagging_pair(readable: true, inscription: "Three hours forty after noon.")
    Item::TemplateRefresh.new(@story).refresh!

    assert_empty Item::TemplateRefresh.new(@story).lags
  end

  test "only: narrows to one game" do
    _template, mine = lagging_pair(readable: true, inscription: "Three hours forty after noon.")
    other = create(:playthrough, story: @story, character: @protagonist, current_location: @office)
    theirs = create(:item, :lying, location: @office, playthrough: other, template: mine.template,
                                   name: mine.name, description: mine.description)

    Item::TemplateRefresh.new(@story).refresh!(only: @playthrough)

    assert_predicate mine.reload, :readable?
    assert_not_predicate theirs.reload, :readable?
  end
end
