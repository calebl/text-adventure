# The one way into a System One model, and the counterpart of `BaseAgent`
# rather than a kind of it.
#
# `BaseAgent` wraps a CHAT: instructions, a schema, a conversation that is a row,
# a rotation over models that all speak the same way. A System One request is
# none of that. It sends a `state` object and a MAP OF TYPED QUESTIONS, and gets
# back one typed answer per question -- no messages, no history to continue, no
# schema to be ignored, and nothing to rotate to. Pretending it were a chat
# would have meant `#with_schema` and `#ask` that lie about what is sent, so this
# class exposes `#ask_questions(state:, questions:)` and nothing chat-shaped.
#
# WHAT IT IS FOR: `Playthrough::Classifier::Cascade`, which asks one request of
# ten questions in front of the turn and composes the answer in the engine. See
# that class's header for the rules and `Playthrough::Classifier::Request` for
# the questions.
#
# THE KEY IS THE SWITCH AND THERE IS NO FLAG. `.configured?` is the whole of it:
# with `TYPESAFE_API_KEY` in the environment the cascade runs, and without it the
# classifier makes the one model call it always made. **An absent key is not an
# error.** It is deliberately NOT `BaseAgent::NoModelConfiguredError` either --
# that names a game with no model at all, which is a broken install; this names
# an ordinary machine, including every test run and every developer checkout.
#
# A FAILURE HERE NEVER BLOCKS A TURN. Every way this class can fail -- a
# timeout, an HTTP error, a body that will not parse, an answer set that does not
# match the questions sent, a choice outside the options sent -- is one error
# family, `Unavailable`, and the one thing its caller does with it is make the
# call it would have made anyway. None of them is an engine refusal: a refusal is
# a reading of the player's line, and these are facts about the network.
class SystemOneAgent
  # The environment variable that turns the cascade on. Read, never logged,
  # never written to a receipt, a message row or a scene -- `scenes.resolved_by`
  # records that a key was PRESENT and never what it was.
  API_KEY_VARIABLE = "TYPESAFE_API_KEY".freeze

  ENDPOINT = URI("https://api.typesafe.ai/v1/systemone").freeze

  # TypeSafe's flagship System One model, by its floating alias. The escalation
  # target is a different model at a different vendor and is named in
  # `BaseAgent::REMOTE_MODEL_IDS`; the two are deliberately not in one list,
  # because nothing rotates between them -- the cascade escalates, which is a
  # decision the engine takes on a reading rather than on a failure.
  MODEL = "jev-latest".freeze

  # HOW LONG A TURN WILL WAIT FOR THIS, and it is a live-turn number rather than
  # the benchmark's. The player is waiting on narration and this call sits in
  # front of it; the measured median for a request of this size is about a third
  # of a second, so a wait this long is already many times the answer. What
  # running out costs is one extra Mistral call and no turn at all -- see
  # `#ask_questions`.
  TIMEOUT = 4

  # EVERY WAY THIS CLASS FAILS, and there is one family on purpose. The caller
  # does the same thing with all of them, so telling them apart at the raise
  # site would only invite a caller to start branching on the network.
  class Unavailable < StandardError; end

  # The answer came back and cannot be believed: a missing id, an id nobody
  # asked for, an answer of the wrong type, or a choice outside the options that
  # were sent. Still `Unavailable`, because the outcome is the same.
  class UnusableAnswerError < Unavailable; end

  # WHETHER THIS ENVIRONMENT HAS A SYSTEM ONE KEY AT ALL. The cascade's only
  # switch; see the header.
  def self.configured? = ENV[API_KEY_VARIABLE].present?

  attr_reader :purpose

  # `transport` is the seam the offline engine sweep and the tests stand a
  # fixture in at, the way `BaseAgent.new` is stubbed everywhere else. It answers
  # one method, `#call(body)`, and returns the parsed response body.
  def initialize(purpose: nil, transport: nil)
    @purpose = purpose
    @transport = transport
  end

  # Sends one request and returns an `Answers`. Raises `Unavailable` for every
  # failure, including a key that has gone missing between `.configured?` and
  # here.
  #
  # `questions` is the map the API takes, keyed by ids the caller chose; the ids
  # are not sent to the model and exist only so code can read the answers back.
  def ask_questions(state:, questions:)
    raise Unavailable, "no #{API_KEY_VARIABLE} in this environment" unless self.class.configured?
    raise Unavailable, "a System One request with no questions" if questions.blank?

    body = { model: MODEL, state: state, questions: questions }
    Answers.new(parse(transport.call(body)), questions)
  end

  private

  def transport = @transport ||= Http.new

  def parse(payload)
    raise UnusableAnswerError, "the provider answered #{payload.class} rather than a body" unless payload.is_a?(Hash)

    payload
  end

  # ONE REQUEST'S ANSWERS, VERIFIED AGAINST THE QUESTIONS THAT WERE SENT.
  #
  # The verification is the point and it is why this is a class rather than a
  # Hash. A Choice is only a closed set because the app closed it, and an answer
  # naming something outside the criteria that were sent would be exactly the
  # out-of-bounds reading the whole design exists to make impossible. So it is
  # checked HERE, once, rather than by each rule that reads an answer.
  class Answers
    attr_reader :usage

    def initialize(payload, questions)
      @answers = payload["answers"]
      @usage = payload["usage"]
      @questions = questions.deep_stringify_keys

      raise UnusableAnswerError, "the provider answered no `answers` map" unless @answers.is_a?(Hash)

      missing = @questions.keys - @answers.keys
      raise UnusableAnswerError, "the provider did not answer #{missing.join(", ")}" if missing.any?
    end

    # The option chosen for one Choice question, verified to be one of the
    # options that question was sent.
    def choice(id)
      answer = answer_of(id, "choice")
      chosen = answer["choice"]
      options = @questions.fetch(id.to_s).fetch("criteria").keys
      unless options.include?(chosen.to_s)
        raise UnusableAnswerError, "#{id} answered #{chosen.inspect}, which is not one of the options sent"
      end

      chosen.to_s
    end

    # The yes probability for one Noul question, as a Float in 0..1.
    def noul(id)
      reading = answer_of(id, "noul")["noul"]
      unless reading.is_a?(Numeric) && reading >= 0 && reading <= 1
        raise UnusableAnswerError, "#{id} answered #{reading.inspect} rather than a probability"
      end

      reading.to_f
    end

    # Whether a question was asked at all. A target question whose record set is
    # empty is not sent -- see `Playthrough::Classifier::Request` -- and its
    # intent resolves to nothing by construction rather than by an answer.
    def asked?(id) = @questions.key?(id.to_s)

    private

    def answer_of(id, type)
      answer = @answers[id.to_s]
      raise UnusableAnswerError, "#{id} was answered #{answer.class}" unless answer.is_a?(Hash)
      raise UnusableAnswerError, "#{id} came back as a #{answer["type"]} rather than a #{type}" unless answer["type"] == type

      answer
    end
  end

  # The real request, over Net::HTTP because the app has no HTTP client of its
  # own and this needs one method. Timeouts are bounded on both ends: a provider
  # that accepts a connection and then says nothing is the failure mode a read
  # timeout exists for, and it is the one that would otherwise hold a turn open.
  class Http
    def call(body)
      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{ENV.fetch(API_KEY_VARIABLE)}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port, use_ssl: true,
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end

      # THE STATUS TEXT AND NEVER THE BODY. A 4xx body details the offending
      # field and a 401 body is about a credential; neither belongs in a log
      # line that a player's turn wrote.
      unless response.is_a?(Net::HTTPSuccess)
        raise Unavailable, "the provider answered #{response.code} #{response.message}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise UnusableAnswerError, "the provider answered something that is not JSON (#{e.class})"
    rescue Unavailable
      raise
    rescue StandardError => e
      raise Unavailable, "#{e.class}: #{e.message}"
    end
  end
end
