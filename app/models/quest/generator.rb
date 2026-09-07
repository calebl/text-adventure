# THE ONE EXTRA MODEL CALL A GENERATED WORLD PAYS FOR KNOWING WHERE IT IS GOING.
#
# THE CAPTAIN'S CALL 3, 2026-09-06: **"a: yes, one separate call -- 7 to 8 per
# world."** A world is generated rarely and played many times, so a per-world
# round trip is the cheapest place in the app to spend one; and a SEPARATE call
# is what keeps `Story::Generator`'s closing sentence -- *"Leave the ending
# open. You are starting a story, not outlining one."* -- true. One answer
# cannot be asked to both leave the ending open and state it.
#
# IT CREATES NO ROWS BUT ITS OWN. Every `quest_steps.target_id` it writes is
# NULL: the arc states what the world must contain, and the registries decide
# when it does (`Quest::Binder`). So `Story::Doctor` looks at a brand-new
# generated world and reports an open arc with unbound steps, which is the
# correct and expected state of one -- `quests.origin` is the column that lets
# it say so without guessing, and it is why this class writes `generated`.
#
# WHERE IT RUNS: inside `Story::FirstScreen`, after the protagonist and BEFORE
# the opening room is realized. The order is that class's to own and its header
# has the reasoning; the part that belongs here is why it is not last. The
# opening room is the first thing any generated world realizes, and once the
# story block reaches `Location::Generator#story_context` it is the first room
# that can be told where the story is going -- a call made after the room was
# written would have missed the one room every player starts in.
#
# WHAT IT COSTS: one call, roughly the shape of `Story::Generator`'s own
# (measured at 1,679 in / 340 out on story 7). Nothing per room and nothing per
# turn -- the beats are record predicates.
#
# WHAT HAPPENS WHEN IT FAILS, and it is the reason `#generate!` answers nil
# rather than raising: a world with no arc is the world every world in this
# repository was until this shipped. It is playable, it is exportable, the
# doctor reports `story_without_a_conclusion` and a person can write a `quests:`
# block by hand. A world with no OPENING ROOM is not any of those things, which
# is why `Story::FirstScreen`'s other three steps do raise. The arc is the one
# step of the first screen the world can be born without.
class Quest::Generator
  include SanitizesGeneratedText

  attr_reader :story

  def initialize(story)
    @story = story
  end

  # Writes the story's main arc and returns it, or nil if the call failed or
  # answered with nothing usable. One transaction: an arc with beats and no
  # ending is one nothing can finish, and `Story::Doctor` would report a state
  # that only exists because a save was interrupted.
  def generate!
    content = ask
    return nil if content.nil?

    steps = Array(content["steps"]).select { |row| usable_step?(row) }
    outcomes = Array(content["outcomes"]).select { |row| usable_outcome?(row) }
    return nil if steps.empty? || outcomes.empty?

    Quest.transaction do
      quest = story.quests.create!(
        title: title_for(content),
        premise: sanitize_string(content["premise"].to_s),
        status: "open",
        contributes: true,
        origin: "generated"
      )

      steps.each_with_index { |row, index| write_step!(quest, row, index + 1) }
      write_outcomes!(quest, outcomes)
      quest
    end
  end

  def system_prompt
    <<~PROMPT
      You say where a story is going, in the fewest moving parts that can carry
      it. You name a place, a person or a thing per beat and nothing else: no
      route between them, no scenes, no chapter headings, and never how the
      player gets from one to the next. The world is built by somebody else and
      may take a long time to grow what you name.

      DO NOT INCLUDE EMOJIS IN YOUR RESPONSE.
    PROMPT
  end

  # WHAT IT IS TOLD: the universe, the story's own two paragraphs, and the room
  # it opens in. Everything else the world has is one unrealized stub and a
  # protagonist, so there is nothing else honest to hand it.
  #
  # THE OPENING ROOM IS NAMED AS A THING THAT ALREADY EXISTS, and it is the one
  # place in this prompt where the boundary matters: the arc may use it, and
  # everything else it names is something the world does not have.
  def generation_prompt
    <<~PROMPT
      ## Universe Details
      #{story.universe.prompt_details(:place)}

      ## The Story So Far
      title: #{story.title}
      genre: #{story.genre}
      preface: #{story.preface}
      summary: #{story.summary}

      ## What This World Already Has
      One room, called #{opening_name.inspect}, and the person playing. Nothing else
      exists yet -- no other place, nobody else, and not one object.

      ## Instructions
      Say where this story is going.
      - Give it #{Quest::Schema::STEPS.first} to #{Quest::Schema::STEPS.last} beats, in the order they would most naturally happen
      - Each beat names ONE thing: a place to stand in, a person to speak to, or
        a thing to be carrying. Name it as a player would say it
      - You are NOT creating those things. You are saying what this world must
        come to contain. Something else builds them, later, as the player explores
      - Do not plan a route. Two beats in a row may be in the same place or a
        world apart; nothing here decides how anybody gets between them
      - Name #{opening_name.inspect} only if the story genuinely returns to it. Everything else
        you name is new
      - The endings are what the player reads when the story closes. Exactly one
        of them is the one this world is built toward
      - Do not resolve the preface. The preface asks a question; these are the
        ways it can be answered
    PROMPT
  end

  private

  # A FAILED CALL IS A WORLD WITHOUT AN ARC, not a world that failed to be born
  # -- see the header. `BaseAgent` has already worked its whole rotation by the
  # time anything raises here, so this is the end of the line rather than a
  # retry.
  def ask
    agent = BaseAgent.new.with_instructions(system_prompt)
    agent.with_schema(Quest::Schema).ask(generation_prompt).content
  rescue StandardError
    nil
  end

  def write_step!(quest, row, position)
    quest.steps.create!(
      position: position,
      summary: sanitize_string(row["summary"].to_s),
      trigger_kind: row["trigger"],
      target_name: sanitize_string(row["target"].to_s),
      teaser: sanitize_string(row["teaser"].to_s).presence
    )
  end

  # EXACTLY ONE DEFAULT, WHICHEVER WAY THE ANSWER CAME BACK. The schema asks for
  # one and the prompt says so, and neither can enforce it -- so the engine
  # takes the first ending the answer marked and, if it marked none, the first
  # ending it wrote. A world born with two defaults would be a world whose
  # conclusion is decided by row order, which is the state
  # `Story::Doctor#quests_with_two_defaults` exists to report and this exists to
  # prevent.
  #
  # AND A DUPLICATE LABEL IS DROPPED rather than raising: `Quest::Outcome` keys
  # on (quest, name), so two endings called the same thing are one ending and a
  # lost sentence, which is better than a world with no arc at all.
  def write_outcomes!(quest, rows)
    chosen = rows.detect { |row| row["is_default"] == true } || rows.first
    seen = []

    rows.each do |row|
      name = sanitize_string(row["name"].to_s).parameterize.presence || "ending-#{seen.size + 1}"
      next if seen.include?(name)

      seen << name
      quest.outcomes.create!(name: name, summary: sanitize_string(row["summary"].to_s),
                             is_default: row.equal?(chosen))
    end
  end

  # A step the engine could never act on is dropped rather than written: an
  # empty summary is a line the narrator would be handed blank, and a trigger
  # outside the fixed table is one nothing evaluates. `Quest::Step` refuses both,
  # so this is the difference between an arc with four beats and no arc at all.
  def usable_step?(row)
    row.is_a?(Hash) && row["summary"].to_s.strip.present? &&
      Quest::Schema::TRIGGERS.include?(row["trigger"]) && row["target"].to_s.strip.present?
  end

  def usable_outcome?(row) = row.is_a?(Hash) && row["summary"].to_s.strip.present?

  # THE TITLE, AND A FALLBACK THAT IS NOT A GUESS. `quests.title` is the natural
  # key a seed file re-asserts an arc under, so an empty one would be a row the
  # exporter could not write and the loader could not find again. The story's
  # own title is the honest stand-in: it is what this arc is about.
  def title_for(content)
    sanitize_string(content["title"].to_s).presence || story.title
  end

  def opening_name = story.opening_location&.name.to_s
end
