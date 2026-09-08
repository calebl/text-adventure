require "test_helper"

# ONE DRAW'S PAGE AND ITS VERDICT, AND THE ONE ENDPOINT IN THIS NAMESPACE THAT
# SPENDS MONEY.
#
# THE SPEND IS A POST AND NOTHING ELSE REACHES THE RUNNER, which is the rule the
# whole debug surface is under: a page load that bought a call would turn a
# reload into a purchase, and a browser reloads on its own. So the draw is tested
# with the model stood in for, and every other assertion here is offline.
class Lab::Exits::SamplesControllerTest < ActionDispatch::IntegrationTest
  test "the page shows the sequence with the exits answer as its subject" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    get lab_exits_sample_path(sample)

    assert_response :success
    assert_select "h1", text: "draw ##{sample.id}"
    assert_select "h3", text: /the answer, one block per place named/
    assert_select "h3", text: /what the engine did with each pick/
    assert_select ".place h3", text: "The Salt Chandlery"
    assert_select ".place h3", text: "Tide Flats"
  end

  # THE STEP THAT DOES NOT EXIST ON THE OTHER LAB'S PAGE, and the reason this one
  # was asked for: where three quarters of the bands disappeared.
  test "the page says in words when a band was thrown away" do
    sample = create(:lab_exits_sample, :every_pick_discarded)

    get lab_exits_sample_path(sample)

    assert_select "td", text: /the band was thrown away/
  end

  test "the page says what the engine rolled when a band was used" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    get lab_exits_sample_path(sample)

    assert_select "td", text: /rolled a footprint inside/
  end

  test "a band that was never picked is named as a decision not made" do
    sample = create(:lab_exits_sample, :no_band_picked)

    get lab_exits_sample_path(sample)

    assert_select ".v", text: /no band at all/
  end

  test "a failed draw says so and is out of every denominator" do
    sample = create(:lab_exits_sample, :failed)

    get lab_exits_sample_path(sample)

    assert_response :success
    assert_select "h3.warn", text: "the call failed"
  end

  test "a draw whose call was never made says so rather than printing an empty table" do
    sample = create(:lab_exits_sample, :never_asked)

    get lab_exits_sample_path(sample)

    assert_select "p.absent", text: /no exits call was answered/
  end

  # THE VERDICT ON THE SET, and the aspects offered are the set's and not a
  # place's -- the split `Lab::Exits::Sample`'s header argues for.
  test "the verdict form offers the aspects only the whole answer can be wrong about" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    get lab_exits_sample_path(sample)

    Lab::Exits::Sample::ASPECTS.each do |aspect|
      assert_select "input[type=checkbox][name='aspects[]'][value=?]", aspect
    end
    Lab::Exits::Judgement::ASPECTS.each do |aspect|
      assert_select "input[type=checkbox][value=?]", aspect, 0,
                    "a claim about one named place is a judgement and belongs on the vantage's page"
    end
  end

  test "recording a verdict stores it and buys nothing" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    assert_no_difference -> { Lab::Exits::Sample.count } do
      patch lab_exits_sample_path(sample), params: {
        verdict: "weak", aspects: [ "too_many_ways_out" ], note: "three doors out of a dead end"
      }
    end

    assert_redirected_to lab_exits_sample_path(sample)
    assert_equal "weak", sample.reload.verdict
    assert_equal [ "too_many_ways_out" ], sample.aspect_names
  end

  test "a verdict posted with no aspects clears them rather than keeping the old ones" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground, :bad)

    patch lab_exits_sample_path(sample), params: { verdict: "good" }

    assert_empty sample.reload.aspect_names,
                 "the controller passes [] so a changed verdict does not keep the old verdict's aspects"
  end

  # THE SPEND, WITH THE MODEL STOOD IN FOR. What is asserted is that the endpoint
  # writes exactly one row and goes to it -- the draw's own behaviour is
  # `Lab::Exits::RunnerTest`'s.
  test "drawing is a post, writes one row and goes to it" do
    vantage = create(:lab_exits_vantage, world: "The Quay House")

    assert_difference -> { Lab::Exits::Sample.count }, 1 do
      drawing { post lab_exits_vantage_samples_path(vantage) }
    end

    assert_redirected_to lab_exits_sample_path(Lab::Exits::Sample.last)
    assert_equal vantage, Lab::Exits::Sample.last.vantage
  end

  # A PERSON'S MISTAKE GETS A SENTENCE ON THE PAGE, not a stack trace -- and on
  # this lab the commonest one is a name in the `absent` list that the world does
  # not have.
  test "a place off the books that the world does not have comes back as a flash" do
    vantage = create(:lab_exits_vantage, world: "The Quay House", absent: "The Drowned Compact")

    assert_no_difference -> { Lab::Exits::Sample.count } do
      drawing { post lab_exits_vantage_samples_path(vantage) }
    end

    assert_redirected_to lab_exits_vantage_path(vantage)
    assert_match(/The Drowned Compact/, flash[:alert])
  end

  test "every endpoint is behind the debug flag, and the one that spends most of all" do
    sample = create(:lab_exits_sample, :one_building_and_open_ground)

    Playthrough::Debug.stub(:enabled?, false) do
      get lab_exits_sample_path(sample)
      assert_response :not_found

      patch lab_exits_sample_path(sample), params: { verdict: "good" }
      assert_response :not_found

      assert_no_difference -> { Lab::Exits::Sample.count } do
        post lab_exits_vantage_samples_path(sample.vantage)
      end
      assert_response :not_found
    end
  end

  private

  def drawing(&block)
    stub = lambda do |*args, **options|
      RealizingAgent.new(nil, purpose: options[:purpose], instructions: args.first)
    end

    BaseAgent.stub(:new, stub, &block)
  end
end
