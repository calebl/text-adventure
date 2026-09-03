# DOES OPENROUTER CACHE THIS APP'S PROMPTS, AND WOULD IT SAVE ANYTHING?
#
# RUN BY HAND, AND IT SPENDS MONEY -- about a cent. It cannot be a test for
# exactly that reason, so the answer it produced lives in the header of
# `Eval::Cost` and this is how to check it.
#
# TWO HALVES, because one on its own proves nothing:
#
#   1. REAL PROMPTS, lifted out of a finished eval run and replayed in the
#      shape the app sends them -- a fresh chat per call with identical
#      instructions, so the only thing two consecutive calls of one agent share
#      is the prefix. Call A would write any cache, call B would read it.
#
#   2. A LADDER OF LONG PREFIXES, to tell "this provider does not cache" apart
#      from "our prompts are too short to qualify". The prefix is built from
#      DISTINCT prose out of every run -- a first attempt used twelve copies of
#      the same passage and reported thousands of cached tokens on call A,
#      which is repetition inside one request and says nothing about a cache
#      surviving between them. A hit on B and not on A is the only shape that
#      counts, and it appears at PREFIX_CHARS=10000 and not at 8000.
#
# PREFIX_CHARS sets the ladder's rung (default 24000). EVAL_MODEL picks the
# model. Nothing is written to the development database: every call goes to a
# throwaway copy of `tmp/eval/base.sqlite3`, because the development database is
# the captain's own playthrough corpus and stray probe conversations would turn
# up in `rake game:score`.
require "sqlite3"
require "fileutils"

FileUtils.cp("tmp/eval/base.sqlite3", "tmp/eval/cache_probe.sqlite3")
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", database: "tmp/eval/cache_probe.sqlite3", timeout: 15_000, pool: 5
)

MODEL  = ENV.fetch("EVAL_MODEL", BaseAgent::REMOTE_MODEL_IDS.first)
RUNS   = ENV.fetch("PROBE_RUNS", "tmp/eval/main20/runs")
PREFIX = ENV.fetch("PREFIX_CHARS", "24000").to_i

OPTIONS = [ { model: MODEL, provider: :openrouter, assume_model_exists: true } ].freeze

def lcp(a, b)
  n = [ a.length, b.length ].min
  i = 0
  i += 1 while i < n && a[i] == b[i]
  i
end

# One call, reported as the provider reported it. `cached_tokens` is
# `prompt_tokens_details.cached_tokens` and is the whole answer; `input_tokens`
# is what RubyLLM has already SUBTRACTED it from.
def call(instructions, prompt)
  response = BaseAgent.new(instructions, model_options: OPTIONS).ask(prompt)
  { input: response.input_tokens, cached: response.cached_tokens,
    written: response.cache_creation_tokens, output: response.output_tokens }
end

def probe(label, instructions, prompt_a, prompt_b)
  shared = lcp(instructions + prompt_a, instructions + prompt_b)
  a = call(instructions, prompt_a)
  b = call(instructions, prompt_b)

  puts format("  %-14s shared=%6d chars   A: in=%5d cached=%-6s   B: in=%5d cached=%-6s",
              label, shared, a[:input], a[:cached].inspect, b[:input], b[:cached].inspect)
  b[:cached].to_i
rescue => e
  puts format("  %-14s FAILED %s: %s", label, e.class, e.message.to_s[0, 120])
  0
end

# The first exchange of every conversation in a run, grouped by the agent that
# held it -- the system prompt identifies it, and no two agents share one.
def pairs_from(db)
  con = SQLite3::Database.new(db)
  rows = con.execute("select chat_id, role, coalesce(content,''), id from messages order by chat_id, id")
  con.close

  rows.group_by(&:first).map { |_, msgs|
    { sys: msgs.find { |_, role, _, _| role == "system" }&.at(2).to_s,
      user: msgs.find { |_, role, _, _| role == "user" }&.at(2).to_s }
  }.reject { |chat| chat[:sys].empty? || chat[:user].empty? }
   .group_by { |chat| chat[:sys][0, 50] }
   .filter_map { |_, group| group.first(2) if group.size > 1 }
end

def distinct_prose(directory, chars)
  seen = {}
  Dir["#{directory}/*.sqlite3"].sort.each do |db|
    con = SQLite3::Database.new(db)
    con.execute("select coalesce(content,'') from messages where role='assistant'")
       .flatten.each { |text| seen[text] = true if text.length > 200 }
    con.close
  end

  seen.keys.join("\n\n")[0, chars].to_s
end

puts "model: #{MODEL}"
puts "runs:  #{RUNS}"
puts

cached = 0

puts "REAL PROMPTS out of a finished run:"
db = Dir["#{RUNS}/*.sqlite3"].sort.first
if db
  pairs_from(db).sort_by { |a, _| -(a[:sys].length + a[:user].length) }
                .first(3).each_with_index do |(a, b), i|
    cached += probe("agent-#{i + 1}", a[:sys], a[:user], b[:user])
  end
else
  puts "  no run databases under #{RUNS} -- generate a set first (rake eval:run)"
end

puts
puts "A LONG PREFIX of distinct prose:"
prose = distinct_prose(RUNS, PREFIX)
if prose.length > 1_000
  cached += probe("prefix-#{PREFIX}", "You are a careful reader of the archive below.\n\n#{prose}",
                  "Answer in one word: is the archive above fiction?",
                  "Answer in one word: is the archive above prose?")
else
  puts "  not enough prose in #{RUNS} to build a #{PREFIX}-char prefix"
end

puts
puts cached.positive? ? "CACHING OBSERVED on the second call." : "NO CACHING OBSERVED anywhere."
puts "A hit needs a prompt over the provider's minimum -- 2,048 tokens when this"
puts "was measured. See the header of Eval::Cost for what that means for a sweep."
