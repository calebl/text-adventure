require "test_helper"

# THE LAB'S PAGES, AND THE ONE RULE THAT KEEPS THEM HONEST: A GET NEVER BUYS A
# CALL.
#
# Everything asserted here is offline. Typing a kind, declaring an expectation,
# reading a rate and reading a sample are all record work -- the only endpoint in
# the lab that reaches a model is `POST .../samples`, which has its own test and
# its own fake.
class Lab::KindsControllerTest < ActionDispatch::IntegrationTest
  test "the index lists the kinds and offers the form for one more" do
    kind = create(:lab_realization_kind, :a_building, name: "The Fishmonger's Warehouse")

    get lab_kinds_path

    assert_response :success
    assert_select "h1", text: "the realization lab"
    assert_select "table td a", text: "The Fishmonger's Warehouse"
    assert_select "select[name='kind[world]'] option", text: kind.world

    # THE FORM HAS NO PROMPT FIELD AND MUST NEVER HAVE ONE -- a lab with one
    # would be a second prompt source with no baseline. This is that rule as an
    # assertion.
    assert_select "textarea[name='kind[teaser]']", 1
    assert_select "[name*='prompt']", 0
    assert_select "[name*='instructions']", 0
  end

  test "the index offers every label of every pick as a checkbox and none of them ticked" do
    get lab_kinds_path

    Lab::Realization.picks.each do |pick|
      assert_select "input[type=checkbox][name='expects[#{pick.name}][]']", pick.values.size
    end
    assert_select "input[type=checkbox][checked]", 0, "don't care is the default"
  end

  test "creating a kind stores the facts and the expectation and goes to its page" do
    assert_difference -> { Lab::Realization::Kind.count }, 1 do
      post lab_kinds_path, params: {
        kind: { world: "The Quay House", name: "The Fishmonger's Warehouse",
                teaser: "A flooded warehouse.", inside: "a few rooms", danger: "uneasy" },
        expects: { "storeys_below" => [ "a cellar", "deep" ], "hazard" => [ "flooded" ] }
      }
    end

    kind = Lab::Realization::Kind.last

    assert_redirected_to lab_kind_path(kind)
    assert_equal "a few rooms", kind.inside
    assert_equal [ "a cellar", "deep" ], kind.expects(Lab::Realization.pick("storeys_below"))
    assert_nil kind.expects(Lab::Realization.pick("gradient")), "an unticked pick is don't care"
  end

  test "a kind nothing can be staged from comes back with the complaint on the form" do
    assert_no_difference -> { Lab::Realization::Kind.count } do
      post lab_kinds_path, params: { kind: { world: "The Drowned Compact", name: "x", teaser: "y" } }
    end

    assert_response :unprocessable_content
    assert_match "not a world the lab has a file for", response.body
  end

  # THE EXPECTATION IS EDITABLE AFTER THE FACT AND EDITING IT BUYS NOTHING, which
  # is the property worth designing the page around: draw ten, look at them, THEN
  # decide what you think the picks should have been.
  test "declaring an expectation later scores the samples already drawn" do
    kind = create(:lab_realization_kind, :a_building)
    create(:lab_realization_sample, :a_building, kind: kind)

    get lab_kind_path(kind)

    assert_response :success
    assert_match "no expectation declared", response.body

    patch lab_kind_path(kind), params: { expects: { "hazard" => [ "flooded" ] } }

    assert_redirected_to lab_kind_path(kind)

    get lab_kind_path(kind)

    assert_match "1 of 1", response.body
    assert_match "not established", response.body
  end

  # THE FACTS ARE NOT EDITABLE, because a kind's samples were drawn against the
  # words it was drawn with -- `Eval::Realization.digest`'s objection to a corpus
  # edited between two runs, one level down.
  test "an update cannot rewrite the facts a kind was drawn against" do
    kind = create(:lab_realization_kind, name: "The Fishmonger's Warehouse")

    patch lab_kind_path(kind), params: { kind: { name: "Somewhere Else" }, expects: {} }

    assert_equal "The Fishmonger's Warehouse", kind.reload.name
  end

  test "a page for a kind with an expectation nothing can answer says so in words" do
    kind = create(:lab_realization_kind, :a_building, :expecting_no_insides)

    get lab_kind_path(kind)

    assert_response :success
    assert_match "never answered for this kind", response.body
  end

  test "deleting a kind takes its samples and returns to the index" do
    kind = create(:lab_realization_kind)
    create(:lab_realization_sample, :a_room, kind: kind)

    assert_difference -> { Lab::Realization::Sample.count }, -1 do
      delete lab_kind_path(kind)
    end

    assert_redirected_to lab_kinds_path
  end

  # THE GATE IS IN THE CONTROLLER AND NOT ON THE LINK. This app has no auth at
  # all, and this is the one instrument page that can be made to spend money.
  test "every lab page is not found with the instrument off" do
    kind = create(:lab_realization_kind)
    sample = create(:lab_realization_sample, :a_room, kind: kind)

    Playthrough::Debug.stub(:enabled?, false) do
      get lab_kinds_path
      assert_response :not_found

      get lab_kind_path(kind)
      assert_response :not_found

      get lab_sample_path(sample)
      assert_response :not_found

      assert_no_difference -> { Lab::Realization::Sample.count } do
        post lab_kind_samples_path(kind)
      end
      assert_response :not_found

      patch lab_sample_path(sample), params: { verdict: "good" }
      assert_response :not_found
      assert_nil sample.reload.verdict
    end
  end
end
