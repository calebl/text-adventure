require "test_helper"

# THE SAMPLE PAGE AND THE ONE ENDPOINT IN THE APP THAT SPENDS MONEY.
#
# The page is the answer to the captain's second sentence -- *"It's still hard
# for me to hold in my head the full sequence of everything that happens each
# turn or as you move into a new room/location"* -- so what is asserted here is
# THE SEQUENCE: every step in it, in order, each marked with whether a model
# answered it or the engine decided it.
class Lab::SamplesControllerTest < ActionDispatch::IntegrationTest
  test "the page renders the whole sequence of a rooms draw, marked with who decided each step" do
    kind = create(:lab_realization_kind, :expecting_no_insides)
    sample = create(:lab_realization_sample, :a_room, kind: kind)

    get lab_sample_path(sample)

    assert_response :success

    # ONE COLUMN IN SEQUENCE, and the marks are the README's turn-diagram
    # convention: purple for a model call, teal for the app deciding.
    assert_select "div.step", 7
    assert_select "div.step.model span.who.model"
    assert_select "div.step.engine span.who.engine"

    # The prompt as SENT, and the raw answer beside it.
    assert_select "details.exchange summary", text: /the detail prompt, as sent/
    assert_select "details.exchange summary", text: /the raw exits answer/

    # The per-exit picks, scored against the expectation: this kind wants no
    # insides and got none, so the mark is a hit.
    assert_select "span.pick.hit", text: Location::Parameters::NO_INSIDE
    assert_select "span.pick.unscored", text: "a person or two"

    # The prose, and what the registries made of the answer.
    assert_select "h3", text: "description"
    assert_match "Black water stands a foot deep.", response.body
    assert_select "table td", text: "The Chandler's Lane"
  end

  test "a buildings draw shows the picks, the layout and the exits call that was never made" do
    kind = create(:lab_realization_kind, :a_building, :expecting_a_cellar)
    sample = create(:lab_realization_sample, :a_building, kind: kind)

    get lab_sample_path(sample)

    assert_response :success

    # TWO MORE STEPS THAN A ROOM'S: the picks, and the inside the engine laid
    # out from them.
    assert_select "div.step", 9

    # THE PICKS ARE THE FIVE THE PARAMETERS BLOCK CARRIES, scored against the
    # expectation -- and the one he declared is a hit.
    assert_select "span.pick.hit", text: "a cellar"
    assert_select "span.pick.unscored", text: "flooded"

    # THE LAYOUT IS RENDERED AND NOT SCORED, which is the sharpest rule in the
    # instrument: the pick moves the odds and the die still decides each room.
    assert_match "the inside, laid out", response.body
    assert_match "1 below the ground floor", response.body

    # AND A LAID-OUT PLACE MAKES NO EXITS CALL AT ALL.
    assert_match "there was no call", response.body
  end

  test "a page for a failed draw says which failure it was" do
    sample = create(:lab_realization_sample, :failed)

    get lab_sample_path(sample)

    assert_response :success
    assert_match "the call failed", response.body
    assert_match "BaseAgent::RefusalError", response.body
  end

  test "the verdict form offers three words and six aspects and none of them required" do
    sample = create(:lab_realization_sample, :a_room)

    get lab_sample_path(sample)

    Lab::Realization::Sample::VERDICTS.each do |verdict|
      assert_select "input[type=radio][name=verdict][value=#{verdict}]", 1
    end
    assert_select "input[type=checkbox][name='aspects[]']", Lab::Realization::Sample::ASPECTS.size
    assert_select "input[required]", 0
  end

  test "recording a verdict, amending it and clearing it are all the same request" do
    sample = create(:lab_realization_sample, :a_room)

    patch lab_sample_path(sample), params: { verdict: "bad", aspects: %w[prose exits], note: "empty room" }

    assert_redirected_to lab_sample_path(sample)
    assert_equal "bad", sample.reload.verdict
    assert_equal %w[prose exits], sample.aspect_names

    patch lab_sample_path(sample), params: { verdict: "" }

    assert_nil sample.reload.verdict
  end

  # THE ONE PLACE MONEY IS SPENT, AND IT IS A POST. A page load that bought a
  # call would turn a reload into a purchase, and a browser reloads on its own.
  test "drawing a sample is a post, and it lands on the sample it drew" do
    kind = create(:lab_realization_kind, world: "The Quay House")

    assert_difference -> { kind.samples.count }, 1 do
      Lab::Realization::Runner.stub(:new, ->(_kind, **) { StubRunner.new(kind) }) do
        post lab_kind_samples_path(kind)
      end
    end

    assert_redirected_to lab_sample_path(kind.samples.last)
  end

  test "a kind that cannot be staged says so on the kinds own page" do
    kind = create(:lab_realization_kind, world: "The Quay House", reached_from: "Nowhere At All")

    assert_no_difference -> { Lab::Realization::Sample.count } do
      post lab_kind_samples_path(kind)
    end

    assert_redirected_to lab_kind_path(kind)
    follow_redirect!
    assert_match "Nowhere At All", response.body
  end

  # A DOUBLE THAT WRITES THE ROW AND MAKES NO CALL. The runner's own test drives
  # the real thing against a fake agent; this one is about the endpoint, and an
  # endpoint test that realized a room would be paying to assert a redirect.
  class StubRunner
    def initialize(kind) = @kind = kind

    def draw! = @kind.samples.create!(row: { "id" => "lab-kind-#{@kind.id}", "calls" => 2 })
  end
end
