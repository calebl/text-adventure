require "test_helper"

# WHICH PROMPT WROTE A SET, and what a matching digest is allowed to mean.
#
# There are two digests because a prose prompt is instructions AND facts
# interleaved, and they cover different amounts. The tests below are the
# boundary between them, because that boundary is the whole claim: a set that
# said "same prompt" when a fact sentence had been rewritten would let a prompt
# change be judged against itself.
class Eval::Prompt::VersionTest < ActiveSupport::TestCase
  test "one designated prompt per shape, chosen by the lowest id" do
    version = Eval::Prompt::Version.of([ pass(readings: [
      reading(id: "b-take", shape: "take", prompt: "the b prompt"),
      reading(id: "a-take", shape: "take", prompt: "the a prompt"),
      reading(id: "a-move", shape: "move", prompt: "the move prompt")
    ]) ])

    assert_equal %w[move take], version[:prompt_shapes].keys.sort
    assert_equal Playthrough::PromptVersion.of("the a prompt"), version[:prompt_shapes]["take"],
                 "the lowest id, so reordering the corpus does not change the version"
  end

  # THE SECOND DIGEST COVERS WHAT THE FIRST CANNOT: the framing of a fact, the
  # fact sentence itself, and every record `Playthrough::Moment` builds. It is
  # only meaningful because the corpus is fixed -- which is what `corpus_digest`
  # is for.
  test "a changed fact sentence changes the prompt digest and not the instructions digest" do
    before = Eval::Prompt::Version.of([ pass(readings: [
      reading(prompt: "Vance has picked up the stamp.", instructions: "You narrate.")
    ]) ])
    after = Eval::Prompt::Version.of([ pass(readings: [
      reading(prompt: "Vance now carries the stamp.", instructions: "You narrate.")
    ]) ])

    refute_equal before[:prompt_digest], after[:prompt_digest]
    assert_equal before[:instructions_digest], after[:instructions_digest],
                 "the instruction block did not move, and it is the digest a verdict is grouped by"
  end

  test "a changed instruction block changes both" do
    before = Eval::Prompt::Version.of([ pass(readings: [ reading(instructions: "You narrate.") ]) ])
    after = Eval::Prompt::Version.of([ pass(readings: [ reading(instructions: "You narrate briefly.") ]) ])

    refute_equal before[:instructions_digest], after[:instructions_digest]
  end

  # THE GUARD. Every repetition sends the designated case's prompt again, and
  # they are compared: if one case ever produced two different prompts in one
  # run, something in the moment is not constant and every figure in the set is
  # measuring something that moved.
  test "the same case sending two different prompts is reported as unstable" do
    version = Eval::Prompt::Version.of([
      pass(rep: 1, readings: [ reading(prompt: "the office at four") ]),
      pass(rep: 2, readings: [ reading(prompt: "the office at five") ])
    ])

    refute version[:prompt_stable]
  end

  test "the same prompt twice is stable" do
    version = Eval::Prompt::Version.of([
      pass(rep: 1, readings: [ reading(prompt: "the office at four") ]),
      pass(rep: 2, readings: [ reading(prompt: "the office at four") ])
    ])

    assert version[:prompt_stable]
  end

  test "a run whose every call failed has no version rather than a version of nothing" do
    version = Eval::Prompt::Version.of([ pass(readings: [ reading(error: "BaseAgent::RefusalError: no") ]) ])

    assert_nil version[:prompt_digest]
    assert_nil version[:instructions_digest]
  end

  private

  def pass(rep: 1, readings:) = Eval::Prompt::Bench::Pass.new(arm: "fake/model", rep: rep, readings: readings)

  def reading(id: "a-take", shape: "take", prompt: "a prompt", instructions: "You narrate.", error: nil)
    kase = Eval::Prompt::Corpus::Case.new(id: id, position: "office", typed: "do it", act: :take,
                                          target: "ward stamp", shape: shape, why: "because")

    Eval::Prompt::Bench::Reading.new(
      kase: kase, arm: "fake/model", rep: 1, story: "The Unrecorded Hour", pass: "narration",
      text: "You do it.", facts: {}, seconds: 1.0, input_tokens: 1, output_tokens: 1, calls: 1,
      answered_by: "fake/model", instructions: instructions, prompt: prompt,
      missing_fields: [], cap_hits: [], error: error
    )
  end
end
