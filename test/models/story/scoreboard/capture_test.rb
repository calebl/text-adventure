require "test_helper"

# WHAT `rake game:corpus` MAY AND MAY NOT DO TO THE FILE IT WRITES.
#
# `Story::Scoreboard::Capture` is the only thing that writes
# `test/fixtures/files/eval_corpus.json`, and that file is the regression line
# every rate in `rake game:score` is measured against. So the properties pinned
# here are the ones that would be silent if they broke: a passage that changed
# under a corpus, a `lab/` row that disappeared, an `expect` list a capture
# filled in for itself. None of those would fail a test that only checked the
# happy path, and all of them would move a number nobody could explain.
#
# Every test writes to a temporary file, never to the checked-in corpus.
class Story::Scoreboard::CaptureTest < ActiveSupport::TestCase
  def setup
    @story = create(:story, title: "The Unrecorded Hour")
    @playthrough = create(:playthrough, story: @story)
    @first = create(:scene, story: @story, description: "The mantle hisses over the desk.")
    @judged = create(:scene, story: @story, description: "You read the gap in the daybook.",
                             previous_scene: @first, typed: "read the daybook")
    @after = create(:scene, story: @story, description: "The rain goes sideways past the glass.",
                            previous_scene: @judged, typed: "look out of the window")
    @playthrough.update!(current_scene: @after)
  end

  def capture(**options) = Story::Scoreboard::Capture.new(path: relative_path, **options)

  def relative_path = @relative_path ||= "tmp/#{SecureRandom.hex(8)}_corpus.json"

  def file = Rails.root.join(relative_path)

  def write(rows) = File.write(file, "#{JSON.pretty_generate(rows)}\n")

  def rows = JSON.parse(File.read(file))

  def teardown
    File.delete(file) if File.exist?(file)
  end

  def judge!(verdict, note: nil, scene: @judged)
    Playthrough::Feedback.record(playthrough: @playthrough, scene: scene, verdict: verdict, note: note)
  end

  test "it takes the judged turn and the turn either side of it, and nothing else" do
    create(:scene, story: @story, description: "A turn nobody judged, two turns away.",
                   previous_scene: @after)
    judge!("bad", note: "the door closes and I never left")

    result = capture.run

    assert_equal [ "unrecorded/scene-#{@first.id}", "unrecorded/scene-#{@judged.id}",
                   "unrecorded/scene-#{@after.id}" ].sort,
                 result.rows.map { |row| row["label"] }.sort
  end

  test "a captured row carries the verdict, the note and the facts the audit reads" do
    judge!("bad", note: "the door closes and I never left")
    capture.run

    row = rows.find { |candidate| candidate["id"] == @judged.id }

    assert_equal "bad", row["verdict"]
    assert_equal "the door closes and I never left", row["note"]
    assert_equal "read the daybook", row["typed"]
    assert_equal @judged.description, row["text"]
    assert_equal @story.title, row["story"]
  end

  # THE FACTS COME FROM THE RECORDS AND FROM ONE READING OF THEM. A capture that
  # worked out `moved` for itself could disagree with the check that reads it,
  # and the corpus would then be measuring a second opinion.
  test "the facts beside a passage are the audit's own answers" do
    judge!("good")
    capture.run

    facts = Story::Audit.new(@story).facts_for(@judged)
    row = rows.find { |candidate| candidate["id"] == @judged.id }

    assert_equal facts.moved, row["moved"]
    assert_equal facts.still_run, row["still_run"]
    assert_equal facts.present, row["present"]
    assert_equal facts.protagonist, row["protagonist"]
  end

  # A FIRST TURN IS TOLD FROM A TURN THAT STAYED PUT, which is the whole reason
  # `moved` is nullable -- see `Corpus::Passage#follows_a_turn?`.
  test "the turn with nothing before it carries moved as nil" do
    judge!("good")
    capture.run

    assert_nil rows.find { |row| row["id"] == @first.id }["moved"]
    refute_nil rows.find { |row| row["id"] == @judged.id }["moved"]
  end

  test "an amended verdict overwrites the verdict and the note on the row already there" do
    judge!("weak", note: "this has stretched on too long")
    capture.run
    judge!("bad", note: "and now the door closed on its own")

    result = capture.run
    row = rows.find { |candidate| candidate["id"] == @judged.id }

    assert_equal "bad", row["verdict"]
    assert_equal "and now the door closed on its own", row["note"]
    assert_equal [ "updated" ], result.changes.map { |change| change.kind.to_s }
    assert_equal "weak", result.changes.first.was
  end

  # THE PASSAGE AND ITS FACTS ARE FROZEN. `Story::Audit#cast_recorded_by` can
  # answer "who was in the room" differently once the same world has been played
  # again, and a regression line that moved for that reason would not be one.
  test "a captured passage and its facts are never rewritten, only reported" do
    judge!("good")
    capture.run

    was = rows
    was.first["present"] = [ "Somebody The Records Have Since Forgotten" ]
    was.first["text"] = "prose that is not what the records hold any more"
    write(was)

    result = capture.run

    assert_equal was.first["present"], rows.first["present"]
    assert_equal was.first["text"], rows.first["text"]
    assert_equal %w[present text].sort, result.drifts.map(&:field).sort
  end

  # `expect` IS HAND-SIGNED. A capture that wrote it would turn
  # `Story::Scoreboard::CorpusTest` into a test that agrees with whatever the
  # checks currently do.
  test "expect is empty on a new row and untouched on an old one" do
    judge!("bad")
    capture.run

    assert(rows.all? { |row| row["expect"] == [] })

    signed = rows
    signed.first["expect"] = [ "truncated_prose" ]
    write(signed)
    judge!("weak")
    capture.run

    assert_equal [ "truncated_prose" ], rows.first["expect"]
  end

  test "nothing is ever removed, and a lab row is never touched" do
    lab = { "label" => "lab/narration-00", "id" => nil, "story" => @story.title, "room" => "Ward Office 12",
            "typed" => "shoot the lock off the door", "protagonist" => nil, "moved" => false,
            "still_run" => 0, "present" => [], "verdict" => nil, "note" => nil,
            "text" => "You pat your coat and belt.", "expect" => [] }
    write([ lab ])
    judge!("bad")

    capture.run

    assert_equal lab, rows.first
    assert_equal 4, rows.size
  end

  test "a second run over an unchanged database changes nothing" do
    judge!("bad", note: "the door closes and I never left")
    capture.run
    before = File.read(file)

    result = capture.run

    assert_empty result.changes
    assert_equal before, File.read(file)
  end

  test "DRY_RUN leaves the file alone and still reports what it would do" do
    judge!("bad")

    result = capture.run(dry_run: true)

    refute_path_exists file
    assert_equal 3, result.added.size
  end

  # THE HELD-OUT WORLD IS PROSE NO CHECK HAS EVER SEEN, and `EVALUATION.md`
  # forbids putting one of its passages in a fixture. The verdicts on it are
  # counted so the exclusion is visible rather than silent.
  test "a verdict on the held-out world is counted and not captured" do
    held = create(:story, title: Eval::HELD_OUT)
    play = create(:playthrough, story: held)
    scene = create(:scene, story: held, description: "The assize hall smells of brine.")
    play.update!(current_scene: scene)
    Playthrough::Feedback.record(playthrough: play, scene: scene, verdict: "bad")
    judge!("good")

    result = capture.run

    assert_equal 1, result.held_out_verdicts
    assert_empty result.rows.select { |row| row["story"] == Eval::HELD_OUT }
  end

  # A ROW IS THE SCENE IT WAS COPIED FROM, so a label convention that changed
  # could never turn one passage into two.
  test "a row is matched on the scene it came from rather than on its label" do
    judge!("bad")
    capture.run

    renamed = rows.map { |row| row.merge("label" => row["label"].sub("unrecorded/", "hour/")) }
    write(renamed)
    judge!("weak")

    result = capture.run

    assert_equal 3, rows.size
    assert(rows.all? { |row| row["label"].start_with?("hour/") },
           "a matched row keeps the label it was checked in with")
    assert_empty result.added
  end

  # AN INTERACTION IS PROSE THE PLAYER READ TOO, and it declares no protagonist
  # and no turn before it -- which is what drops it out of two denominators in
  # `Story::Scoreboard::Corpus#judgeable_for`.
  test "a character's own line is captured as its own passage, with no protagonist and no turn before it" do
    character = create(:character, story: @story)
    interaction = create(:interaction, scene: @judged, character: character,
                                       action: "He sets the pen down without looking up.")
    judge!("bad")

    capture.run
    row = rows.find { |candidate| candidate["label"].include?("/action-") }

    assert_equal "unrecorded/scene-#{@judged.id}/action-#{interaction.id}", row["label"]
    assert_equal interaction.action, row["text"]
    assert_nil row["protagonist"]
    assert_nil row["moved"]
  end

  # THE LABEL THE HAND CAPTURE USED, reproduced exactly: a slug rule that
  # renamed the rows already in the checked-in corpus would read as a file full
  # of new passages.
  test "the checked-in corpus's own labels are what this slug rule produces" do
    corpus = Story::Scoreboard::Corpus.load
    played = corpus.passages.reject { |passage| passage.label.start_with?("lab/") }

    assert(played.all? { |passage| passage.label.start_with?("unrecorded/", "lunar/", "iron/") },
           "an unexpected slug in the checked-in corpus: #{played.map(&:label).uniq.first(5)}")
    assert_equal({ "The Unrecorded Hour" => "unrecorded", "The Lunar Cartographer" => "lunar",
                   "The Iron Gate Descends" => "iron" },
                 played.to_h { |passage| [ passage.story, passage.label.split("/").first ] })
  end

  test "it makes no model call" do
    judge!("bad")

    BaseAgent.stub(:new, ->(*) { raise "a capture must not call a model" }) do
      assert_predicate capture.run.rows, :any?
    end
  end
end
