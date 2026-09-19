# A System One provider that answers from a queued reply instead of the network,
# and the counterpart of `FakeAgent` at the `SystemOneAgent` boundary.
#
# IT BUILDS A REAL `SystemOneAgent::Answers`, on purpose: the verification that
# an answer matches the questions that were sent is the part of that class worth
# exercising, and a fake that handed back its own answer object would test
# nothing but itself. So a queued reply is the BODY a provider returned, and
# everything the real class would refuse, this one refuses too.
#
# A reply is written the short way -- `{"intent" => "take", "target_present" =>
# 0.9}` -- where a String is a Choice and a Number is a Noul. A Hash under an id
# is passed through untouched, which is how a test sends a shape the provider
# should refuse; a whole body (one carrying `"answers"`) is passed through as
# well. A queued exception is raised instead of answered, the way `FakeAgent`
# stands a failed call.
class FakeSystemOne
  # What was sent, so a test can assert over the state and the questions without
  # a second builder.
  attr_reader :states, :questions

  def initialize(*replies)
    @replies = replies
    @states = []
    @questions = []
  end

  def ask_questions(state:, questions:)
    @states << state
    @questions << questions
    raise "FakeSystemOne ran out of queued replies" if @replies.empty?

    reply = @replies.shift
    raise reply if reply.is_a?(Exception) || (reply.is_a?(Class) && reply <= Exception)

    SystemOneAgent::Answers.new(body_for(reply, questions), questions)
  end

  # How many requests this fake was asked for, which is how a test pins that an
  # escalated line made ONE System One call and not two.
  def calls = @states.size

  private

  # EVERY QUESTION IS ANSWERED, because a provider answers every question it was
  # sent -- so a test naming the two or three fields it cares about gets a
  # complete body, and an incomplete body is a thing a test asks for on purpose
  # rather than a thing it forgets. The filler is the uninteresting answer:
  # `nothing` for a Choice, 0.0 for a Noul.
  def body_for(reply, questions)
    return reply if reply.key?("answers")

    answers = questions.to_h do |id, question|
      [ id, reply.key?(id) ? answer_for(reply[id]) : filler_for(question) ]
    end

    { "answers" => answers, "usage" => { "input_tokens" => 0, "output_tokens" => 0 } }
  end

  def filler_for(question)
    question["type"] == "noul" ? answer_for(0.0) : answer_for(Playthrough::IntentSchema::NOTHING)
  end

  def answer_for(value)
    case value
    when Hash then value
    when Numeric then { "type" => "noul", "noul" => value }
    else { "type" => "choice", "choice" => value.to_s, "probabilities" => { value.to_s => 1.0 }, "confidence" => 1.0 }
    end
  end
end
