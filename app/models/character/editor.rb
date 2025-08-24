class Character::Editor
  attr_reader :editor

  def initialize
    @editor = BaseAgent.new
  end

  # identify issues in the character model
  # returns a hash of errors with the keys being the attributes with problems
  def identify_issues(character)
    character.valid?

    # basic error checking for now
    character.errors.messages
  end

  def fix_issues(character, issues)
  end
end
