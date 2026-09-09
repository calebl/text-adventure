require "test_helper"

# WHAT HE SAYS ABOUT ONE PLACE, TYPED BEFORE A DRAW OR JUDGED AFTER ONE.
#
# ONE ENDPOINT AND ONE ACTION, which is the claim this file holds: the captain's
# Call 3 (a) and his Call 4 (c) are two halves of one row keyed on the place, so
# the same POST serves both and neither half clears the other. Two endpoints
# would be two writers of one row and would need a rule about precedence.
#
# IT BUYS NOTHING. Every figure it feeds is computed off sample rows already paid
# for, so a judgement written today re-scores every draw bought before it.
class Lab::Exits::JudgementsControllerTest < ActionDispatch::IntegrationTest
  test "typing an expectation for a place no draw has named creates the row" do
    vantage = create(:lab_exits_vantage)

    assert_difference -> { Lab::Exits::Judgement.count }, 1 do
      post lab_exits_vantage_judgements_path(vantage),
           params: { name: "The Rust Market", expects: { "inside" => [ "a few rooms" ] } }
    end

    judgement = vantage.reload.judgements.sole

    assert_equal "The Rust Market", judgement.name
    assert_equal [ "a few rooms" ], judgement.expects(Lab::Exits.pick("inside"))
    assert judgement.unmet?, "typed and not yet named by a draw"
  end

  test "judging a place a draw named creates the row and lands on it" do
    vantage = create(:lab_exits_vantage)
    create(:lab_exits_sample, :one_building_and_open_ground, vantage: vantage)

    post lab_exits_vantage_judgements_path(vantage),
         params: { name: "The Salt Chandlery", verdict: "bad", aspects: [ "inside_wrong" ],
                   note: "a chandlery is a shop" }

    judgement = vantage.reload.judgements.sole

    assert_equal "bad", judgement.verdict
    assert_equal [ "inside_wrong" ], judgement.aspect_names
    assert_equal "a chandlery is a shop", judgement.note
    assert_redirected_to lab_exits_vantage_path(vantage, anchor: "place-salt-chandlery")
  end

  # THE KEYING, THROUGH THE ENDPOINT. One click has to score every draw that
  # produced that name however the article fell.
  test "two spellings of one place amend one row rather than making two" do
    vantage = create(:lab_exits_vantage)

    post lab_exits_vantage_judgements_path(vantage),
         params: { name: "The Rust Market", expects: { "inside" => [ "a few rooms" ] } }

    assert_no_difference -> { Lab::Exits::Judgement.count } do
      post lab_exits_vantage_judgements_path(vantage), params: { name: "rust market", verdict: "good" }
    end

    judgement = vantage.reload.judgements.sole

    assert_equal "good", judgement.verdict
    assert_equal [ "a few rooms" ], judgement.expects(Lab::Exits.pick("inside")),
                 "and the expectation typed under the other spelling survived"
  end

  # NEITHER HALF CLEARS THE OTHER, which is what lets one endpoint serve both.
  test "posting a verdict leaves an expectation alone" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })

    post lab_exits_vantage_judgements_path(vantage), params: { name: "The Rust Market", verdict: "weak" }

    assert_equal [ "a few rooms" ], vantage.reload.judgements.sole.expects(Lab::Exits.pick("inside"))
  end

  test "posting an expectation leaves a verdict alone" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Rust Market", verdict: "weak", aspects: [ "band_wrong" ])

    post lab_exits_vantage_judgements_path(vantage),
         params: { name: "The Rust Market", expects: { "inside" => [ "one room" ] } }

    judgement = vantage.reload.judgements.sole

    assert_equal "weak", judgement.verdict
    assert_equal [ "band_wrong" ], judgement.aspect_names
  end

  test "an emptied expectation clears it rather than allowing nothing" do
    vantage = create(:lab_exits_vantage)
    vantage.judge!("The Rust Market", expects: { "inside" => [ "a few rooms" ] })

    post lab_exits_vantage_judgements_path(vantage),
         params: { name: "The Rust Market", expects: { "population" => [ "nobody" ] } }

    judgement = vantage.reload.judgements.sole

    assert_nil judgement.expects(Lab::Exits.pick("inside")),
               "the form posts every pick, so a pick with nothing ticked is a cleared expectation"
    assert_equal [ "nobody" ], judgement.expects(Lab::Exits.pick("population"))
  end

  test "a post with no place name comes back as a flash and writes nothing" do
    vantage = create(:lab_exits_vantage)

    assert_no_difference -> { Lab::Exits::Judgement.count } do
      post lab_exits_vantage_judgements_path(vantage), params: { name: "  ", verdict: "good" }
    end

    assert_redirected_to lab_exits_vantage_path(vantage)
    assert_predicate flash[:alert], :present?
  end

  test "a label the model is never offered comes back as a flash naming the list" do
    vantage = create(:lab_exits_vantage)

    assert_no_difference -> { Lab::Exits::Judgement.count } do
      post lab_exits_vantage_judgements_path(vantage),
           params: { name: "The Rust Market", expects: { "inside" => [ "a mansion" ] } }
    end

    assert_match(/not on the list the model picks from/, flash[:alert])
  end

  test "a pick this lab is not about is ignored rather than stored" do
    vantage = create(:lab_exits_vantage)

    post lab_exits_vantage_judgements_path(vantage),
         params: { name: "The Rust Market", expects: { "hazard" => [ "flooded" ] } }

    assert_equal [], vantage.reload.judgements.sole.declared.map(&:name)
  end

  test "the endpoint buys nothing" do
    vantage = create(:lab_exits_vantage)

    assert_no_difference -> { Lab::Exits::Sample.count } do
      post lab_exits_vantage_judgements_path(vantage), params: { name: "The Rust Market", verdict: "good" }
    end
  end

  test "the endpoint is behind the debug flag" do
    vantage = create(:lab_exits_vantage)

    Playthrough::Debug.stub(:enabled?, false) do
      assert_no_difference -> { Lab::Exits::Judgement.count } do
        post lab_exits_vantage_judgements_path(vantage), params: { name: "The Rust Market", verdict: "good" }
      end

      assert_response :not_found
    end
  end
end
