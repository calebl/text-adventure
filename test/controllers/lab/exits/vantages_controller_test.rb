require "test_helper"

# THE EXITS LAB'S PAGES, AND THE ONE RULE THAT KEEPS THEM HONEST: A GET NEVER
# BUYS A CALL.
#
# Everything asserted here is offline. Typing a vantage, declaring an
# expectation, judging a place, reading a rate and reading a draw are all record
# work -- the only endpoint in this namespace that reaches a model is
# `POST .../samples`, which has its own test and its own fake.
class Lab::Exits::VantagesControllerTest < ActionDispatch::IntegrationTest
  test "the index lists the vantages and offers the form for one more" do
    vantage = create(:lab_exits_vantage, name: "Harbour Steps")

    get lab_exits_vantages_path

    assert_response :success
    assert_select "h1", text: "the exits lab"
    assert_select "table td a", text: "Harbour Steps"
    assert_select "select[name='vantage[world]'] option", text: vantage.world
  end

  test "the alias the captain asked for reaches the same page" do
    get lab_exits_path

    assert_response :success
    assert_select "h1", text: "the exits lab"
  end

  # THE FORM HAS NO PROMPT FIELD AND MUST NEVER HAVE ONE -- a lab with one would
  # be a second prompt source with no baseline. And no `inside` band either,
  # which is this lab's own version of the same rule: a vantage with a band makes
  # no exits call, so the field would silently cancel the measurement.
  test "the form offers no prompt field and no inside band" do
    get lab_exits_vantages_path

    assert_select "textarea[name='vantage[teaser]']", 1
    assert_select "textarea[name='vantage[absent]']", 1
    assert_select "[name*='prompt']", 0
    assert_select "[name*='instructions']", 0
    assert_select "[name='vantage[inside]']", 0
  end

  test "the form offers every quantifier and none of them chosen" do
    get lab_exits_vantages_path

    Lab::Exits::QUANTIFIER_NAMES.each do |name|
      assert_select "input[type=radio][name='expects_inside_quantifier'][value=?]", name
    end
    assert_select "input[type=radio][name='expects_inside_quantifier'][checked]", 1,
                  "don't care is the default and it is the one that starts chosen"
  end

  test "creating a vantage stores the facts and the quantifier and goes to its page" do
    assert_difference -> { Lab::Exits::Vantage.count }, 1 do
      post lab_exits_vantages_path, params: {
        vantage: { world: "The Quay House", name: "Harbour Steps",
                   teaser: "Wet stone down to the tide line.", danger: "uneasy",
                   absent: "The Custom House\nThe Bonded Cellar" },
        expects_inside_quantifier: "at least one",
        expects_population: [ "nobody", "a person or two" ]
      }
    end

    vantage = Lab::Exits::Vantage.last

    assert_redirected_to lab_exits_vantage_path(vantage)
    assert_equal [ "The Custom House", "The Bonded Cellar" ], vantage.absent_names
    assert_equal "at least one", vantage.expects_inside_quantifier
    assert_equal [ "nobody", "a person or two" ], vantage.expects_population_labels
  end

  test "a vantage the lab has no world file for is refused with the form back" do
    assert_no_difference -> { Lab::Exits::Vantage.count } do
      post lab_exits_vantages_path, params: {
        vantage: { world: "Nowhere In Particular", name: "Harbour Steps", teaser: "Steps." }
      }
    end

    assert_response :unprocessable_content
    assert_select "p.warn"
  end

  test "the page shows the vantage, its rate and a draw button that posts" do
    vantage = create(:lab_exits_vantage, :expecting_a_building, name: "Harbour Steps")
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    get lab_exits_vantage_path(vantage)

    assert_response :success
    assert_select "h1", text: "Harbour Steps"
    assert_select "form[action=?][method=post]", lab_exits_vantage_samples_path(vantage)
    assert_select "table td", text: /the quantifier/
  end

  # THE REFUSAL, ON THE PAGE. A one-sided set gets a sentence and no figure --
  # the captain's Call 5, and the guard against the dominant strategy the exits
  # prompt itself invites.
  test "the index refuses an overall figure while the set is one-sided" do
    vantage = create(:lab_exits_vantage, :expecting_no_insides)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    get lab_exits_vantages_path

    assert_select "p.warn", text: /never picks a building/
  end

  test "the index prints a figure once the set holds both shapes" do
    open_country = create(:lab_exits_vantage, :expecting_no_insides)
    a_lane = create(:lab_exits_vantage, :expecting_a_building)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: open_country)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: a_lane)

    get lab_exits_vantages_path

    assert_select "p.warn", 0
    assert_select "p", text: /draws satisfied their own quantifier/
  end

  # THE COUNTER-FIGURE IS ON THE INDEX AND IS PRINTED BESIDE THE OTHER ONE, never
  # instead of it: the gap between them is the whole point.
  test "the index prints both halves of the reach" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :every_pick_discarded, vantage: vantage)

    get lab_exits_vantages_path

    assert_select ".fields .k", text: "insides given"
    assert_select ".fields .k", text: "insides reaching"
    assert_select ".fields .k", text: "discarded"
  end

  # AN UPDATE BUYS NOTHING AND RE-SCORES ROWS ALREADY PAID FOR, which is the whole
  # reason the expectation is editable after the fact.
  test "declaring an expectation buys nothing and re-scores the draws already bought" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    assert_no_difference -> { Lab::Exits::Sample.count } do
      patch lab_exits_vantage_path(vantage), params: { expects_inside_quantifier: "at least one" }
    end

    assert_redirected_to lab_exits_vantage_path(vantage)
    assert_equal 1, vantage.reload.hit_rate.quantifier.hits
  end

  test "the facts are not editable, so a rate is never computed over draws of a different vantage" do
    vantage = create(:lab_exits_vantage, name: "Harbour Steps", absent: "The Custom House")

    patch lab_exits_vantage_path(vantage), params: {
      vantage: { name: "Somewhere Else", absent: "The Bonded Cellar" },
      expects_inside_quantifier: "none of them"
    }

    vantage.reload

    assert_equal "Harbour Steps", vantage.name
    assert_equal [ "The Custom House" ], vantage.absent_names
    assert_equal "none of them", vantage.expects_inside_quantifier, "and the expectation did take"
  end

  test "an unknown quantifier is refused with the page back" do
    vantage = create(:lab_exits_vantage)

    patch lab_exits_vantage_path(vantage), params: { expects_inside_quantifier: "most of them" }

    assert_response :unprocessable_content
  end

  test "deleting a vantage takes its draws and its judgements and returns to the index" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)
    vantage.judge!("The Salt Chandlery", verdict: "good")

    assert_difference [ "Lab::Exits::Vantage.count", "Lab::Exits::Sample.count",
                        "Lab::Exits::Judgement.count" ], -1 do
      delete lab_exits_vantage_path(vantage)
    end

    assert_redirected_to lab_exits_vantages_path
  end

  # AND THE `absent` LIST IS ESCAPED ON THIS PAGE TOO -- see the same test on
  # `Lab::Exits::SamplesControllerTest` for the defect both pages shipped with.
  # THE WAY OUT OF THE LAB, ON THE PAGE. A GET, and it stays a GET honestly:
  # `Lab::Exits::Promotion` emits text and writes nothing, so reading this panel
  # cannot put the tree out of baseline as a side effect of somebody looking at
  # it.
  test "the page prints the vantage as a corpus case, with its absent list and its quantifier" do
    vantage = create(:lab_exits_vantage, :with_places_off_the_books, :dangerous,
                     :expecting_a_building, name: "Harbour Steps")
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    get lab_exits_vantage_path(vantage)

    assert_response :success
    assert_select "h2", text: "promote it to the bench"
    assert_select "pre", text: /- id: exits-harbour-steps/
    assert_select "pre", text: /expects_inside: at least one/
    assert_select "pre", text: /The Custom House/
    assert_select "pre", text: /shape: #{Lab::Exits::Promotion::SHAPE}/
    assert_select "code", text: /rake lab:exits:promote VANTAGE=#{vantage.id}/
  end

  test "an undrawn vantage is told to draw before it promotes" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building)

    get lab_exits_vantage_path(vantage)

    assert_select ".warn", text: /No draw of this vantage has answered/
  end

  # AND THE PER-NAME RECORDS ARE NOT IN THE PRINTED CASE, which is the half of
  # Call 4 that stays in the lab -- asserted here as well as on the emitter,
  # because this panel is what somebody actually pastes from.
  test "a typed per-place expectation is not in the case the page prints" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building)
    vantage.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })

    get lab_exits_vantage_path(vantage)

    assert_select "pre", text: /expects_inside: at least one/
    assert_select "pre", text: /STAY IN THE LAB/
    assert_select "pre", { text: /expects_exit_inside/, count: 0 }
  end

  # THE NAMES IN THAT PANEL ARE TYPED, TOO, so the escaping rule below covers the
  # promotion as well: `html_safe` anywhere on the emitted case would be an
  # unescaped attribute and `bin/brakeman --no-pager` says so.
  test "a vantage whose name holds markup is escaped in the printed case" do
    vantage = create(:lab_exits_vantage, :dangerous, :expecting_a_building,
                     name: "<img src=x onerror=alert(3)>")

    get lab_exits_vantage_path(vantage)

    assert_response :success
    assert_no_match(/<img src=x onerror/, response.body)
  end

  test "a place taken off the books with markup in its name is escaped" do
    vantage = create(:lab_exits_vantage, absent: "<img src=x onerror=alert(2)>")

    get lab_exits_vantage_path(vantage)

    assert_response :success
    assert_no_match(/<img src=x onerror/, response.body)
  end

  # THE GATE. This app has no auth at all, so an endpoint behind a hidden link is
  # an endpoint anybody with the link can read -- and this one can be made to
  # spend the captain's money.
  test "every page is behind the debug flag" do
    vantage = create(:lab_exits_vantage)

    Playthrough::Debug.stub(:enabled?, false) do
      get lab_exits_vantages_path
      assert_response :not_found

      get lab_exits_vantage_path(vantage)
      assert_response :not_found

      post lab_exits_vantages_path, params: { vantage: { world: "The Quay House", name: "X", teaser: "Y" } }
      assert_response :not_found

      patch lab_exits_vantage_path(vantage), params: { expects_inside_quantifier: "none of them" }
      assert_response :not_found

      delete lab_exits_vantage_path(vantage)
      assert_response :not_found
    end
  end
end
