# THE SIX, FOR SOMEBODY WHO ALREADY EXISTS, IN ONE CALL.
#
# `Character::Generator` writes a whole person and gets the six as part of the
# answer. This is the same six asked for somebody whose sheet is already
# written and already on the record -- the backfill's one model call
# (`Character::DesireBackfill`), and nothing else in the app uses it.
#
# IT ASKS FOR THE SIX AND NOTHING ELSE. The name, the race, the body, the
# backstory, the fears: all of them are ALREADY DECIDED, so all of them are
# stated in the prompt and none of them is in the schema. That is
# `Character::Generator`'s own rule -- asking for a value the prompt just
# supplied is a decision bought twice -- and it is what keeps this from being
# a second character generator that could quietly rewrite somebody.
#
# THE INSTRUCTIONS ARE `Character::Desires`' AND NOT WRITTEN AGAIN, for that
# module's stated reason: there are now three places that ask for a conscious
# desire and they must not come to mean three different things by one.
class Character::DesireWriter
  include SanitizesGeneratedText

  # THE SIX FIELDS ON THEIR OWN, with the whole-sheet path's caps. A backfill
  # is not riding on anybody else's call, so it can afford what
  # `Character::Schema` affords.
  class Schema < RubyLLM::Schema
    string :conscious_desire, description: Character::Desires::CONSCIOUS, max_length: Character::DESIRE_LIMIT
    string :unconscious_desire, description: Character::Desires::UNCONSCIOUS, max_length: Character::DESIRE_LIMIT
    string :recognized_need, description: Character::Desires::RECOGNIZED, max_length: Character::DESIRE_LIMIT
    string :unrecognized_need, description: Character::Desires::UNRECOGNIZED, max_length: Character::DESIRE_LIMIT
    string :desire_pursuit, enum: Character::PURSUIT_NAMES, description: Character::Desires::DESIRE_PURSUIT
    string :need_pursuit, enum: Character::PURSUIT_NAMES, description: Character::Desires::NEED_PURSUIT
  end

  attr_reader :character

  def initialize(character)
    @character = character
  end

  def generate
    content = BaseAgent.new.with_instructions(system_prompt).with_schema(Schema).ask(prompt).content

    { desires: Character::DESIRES.to_h { |field|
        [ field, sanitize_string(content[field.to_s], max_length: Character::DESIRE_LIMIT) ]
      },
      pursuits: Character::PURSUIT_COLUMNS.to_h { |field|
        [ field, sanitize_string(content[field.to_s]).presence ]
      } }
  end

  def system_prompt = Character::Desires.system_prompt

  # EVERYTHING THE MODEL NEEDS AND NOTHING IT COULD CHANGE.
  #
  # The story and the universe so the want belongs to this world; the whole
  # sheet so it belongs to this person; where they are standing, because a
  # desire nobody could act on in a room is the one failure the instructions
  # name twice; and their will, because a will of 15 and a will of 8 are two
  # different relationships to a need somebody cannot see.
  def prompt
    story = character.story

    <<~PROMPT
      ## Story Details:
      title: #{story.title}
      genre: #{story.genre}
      summary: #{story.summary}

      ## Universe Details
      #{story.universe.prompt_details(:character)}

      ## Where They Are
      #{character.location&.name || "Nowhere in particular yet."}

      ## The Person, Already Written
      full name: #{character.fullname}
      nickname: #{character.nickname}
      race: #{character.race&.name} -- #{character.race&.description}
      age: #{character.age}
      sex: #{character.sex_label}
      will: #{character.will || "not rolled"}
      appearance: #{character.appearance}
      personality: #{character.personality}
      backstory: #{character.backstory}
      likes: #{character.likes}
      dislikes: #{character.dislikes}
      fears: #{character.fears}

      Everything above is already true of this person and you are not writing any
      of it again. Write only the six values below, about the person above.

      #{Character::Desires.instructions}
    PROMPT
  end
end
