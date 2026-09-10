require "test_helper"

class Eval::Prompt::BranchesPredicatesTest < ActiveSupport::TestCase
  setup do
    @facts = {
      "bodies" => [ { "name" => "Veythra the Silent", "player" => true, "hp" => 4, "max" => 8 },
                    { "name" => "Gorva the Wanderer", "player" => false, "hp" => 5, "max" => 6 } ],
      "blows" => [ { "attacker" => "Veythra the Silent", "target" => "Gorva the Wanderer", "damage" => 1, "die" => 8 },
                   { "attacker" => "Gorva the Wanderer", "target" => "Veythra the Silent", "damage" => 4, "die" => 6 } ],
      "tolls" => [ { "name" => "Veythra the Silent", "where" => "Iron Gate Chamber", "damage" => 1, "saved" => false } ],
      "throw" => { "item" => "stone weight", "target" => "Gorva the Wanderer", "kind" => "struck" },
      "next_beat" => "Take the signet ring.", "withheld" => [ "Find the dry cell.", "The prince is rescued." ]
    }
  end

  test "explicit damage and body dice contradictions have matching clean controls" do
    flagged :blow_contradicted, "You hit Gorva for 9 hit points."
    flagged :blow_contradicted, "Gorva strikes you for 2 damage."
    flagged :blow_contradicted, "Your blow misses."
    flagged :blow_contradicted, "You hit Lyssa for 1 hit point."
    flagged :blow_contradicted, "Your attack rolls 2d8."
    flagged :blow_contradicted, "Gorva's attack uses 1d10."
    flagged :blow_contradicted, "You roll for initiative."
    flagged :blow_contradicted, "His armor absorbs the blow."
    clean :blow_contradicted, "You hit Gorva for 1 hit point. Gorva strikes you for 4 damage."
    clean :blow_contradicted, "Your attack rolls 1d8. Gorva's attack uses 1d6."
    clean :blow_contradicted, "His armor gleams in the light."
    clean :blow_contradicted, "If your blow missed, Gorva could escape."
    clean :blow_contradicted, "Your blow does not miss."
  end

  test "toll amounts and saves compare with placed tolls" do
    flagged :toll_contradicted, "Iron Gate Chamber costs you 8 hit points."
    clean :toll_contradicted, "You lose 1 hit point."
    @facts["tolls"][0].merge!("saved" => true, "damage" => 0)
    flagged :toll_contradicted, "You lose 1 hit point."
    flagged :toll_contradicted, "You are wounded."
    clean :toll_contradicted, "You lose 0 hit points."
  end

  test "throw participants and result are checked separately from its damage" do
    flagged :throw_contradicted, "You throw the dagger at Gorva."
    flagged :throw_contradicted, "You throw the stone weight at Lyssa."
    flagged :throw_contradicted, "The stone weight misses."
    clean :throw_contradicted, "You throw the stone weight at Gorva."
    clean :throw_contradicted, "The stone weight lies at Gorva's feet."
  end

  test "remaining HP and life or death compare with each body" do
    flagged :body_contradicted, "You have 8 hit points remaining."
    flagged :body_contradicted, "You are unhurt."
    flagged :body_contradicted, "You have 8 of 8 hit points."
    flagged :body_contradicted, "Gorva is dead."
    clean :body_contradicted, "You have 4 hit points remaining. Gorva is alive."
    @facts["bodies"][1]["hp"] = 0
    flagged :body_contradicted, "Gorva is alive."
    clean :body_contradicted, "Gorva is dead."
  end

  test "literal future leakage and denial are bounded and paraphrases remain human-only" do
    flagged :beat_contradicted, "The prince is rescued."
    flagged :beat_contradicted, "You must abandon the task to take the signet ring."
    clean :beat_contradicted, "Take the signet ring."
    clean :beat_contradicted, "The royal captive is free."
    clean :beat_contradicted, "If you find the dry cell, you might free him."
  end

  test "new checks abstain on legacy facts and retain generic checks" do
    scorer = Eval::Prompt::Scorer.new([ row("You look around.", {}) ])
    Eval::Prompt::Branches::Predicates::CHECKS.each_key { |code| assert_equal 0, scorer.judgeable_for(code) }
    assert_equal 1, scorer.judgeable_for(:truncated_prose)
    scorer = Eval::Prompt::Scorer.new([ row("You are dead. You have 20 hit points remaining.", @facts) ])
    assert_equal 1, scorer.judgeable_for(:body_contradicted)
    assert_equal 1, scorer.flagged_for(:body_contradicted).size, "one passage, one flag per predicate"
  end

  private

  def row(text, facts) = { "id" => "case", "text" => text, "facts" => facts }
  def claims(code, text) = Eval::Prompt::Branches::Predicates.claims(code, text, @facts)
  def flagged(code, text) = assert_not_empty(claims(code, text), text)
  def clean(code, text) = assert_empty(claims(code, text), text)
end
