# WHAT ONE TYPED VOLITION CALL COSTS, MEASURED ON THE BYTES THE APP SENDS.
#
#   rake eval:volition_probe        spends: CALLS calls (default 4) under a CAP in USD
#   rake eval:volition_probe_price  free: the per-call price and a projection, from a kept set
#   rake eval:volition_baseline     spends: every staged room REPS times (default 4) under a CAP
#   rake eval:volition_baseline_summary  free: what a kept baseline set shows, recomputed
#
# THE BASELINE ROOMS are `test/fixtures/files/volition_baseline_requests.json`,
# twelve staged rooms that `Playthrough::Volition::BaselineRoomsTest` pins byte
# for byte against the app's own request, exactly as the single fixture above
# is pinned. Only the staged state differs room to room; the questions, and
# the pressure question's criteria, are the app's constants in every one.
#
# The request is `test/fixtures/files/volition_system_one_request.json` -- the
# staged Counting Room with Odile Vance in it. `Playthrough::Volition::SystemOneTest`
# pins that file byte for byte against what `Playthrough::Volition::SystemOne#request`
# builds, so sending the file is sending the app's request without a database.
#
# THE CEILING STOPS RATHER THAN EXCEEDS. Before each call the spend so far plus
# the dearest call seen so far is compared with CAP; a call that could cross it
# is not sent. The first call is priced by CAP alone, which is why CAP should
# sit well above one call.
#
# EVERY CALL LEAVES A PRICED RECEIPT, success or not: the provider's response
# id, `usage` (which carries `usage.cost`), and the answers; a failure keeps the
# status and the full error body and ends the run, because the transport the
# game uses deliberately logs only the status line. OpenRouter's credit reading
# is taken before and after, and the account may be shared, so the receipts'
# own `usage.cost` is the per-call figure and the credit delta is the bracket.
module Eval
  module VolitionProbe
    FIXTURE = Rails.root.join("test/fixtures/files/volition_system_one_request.json")
    ROOMS = Rails.root.join("test/fixtures/files/volition_baseline_requests.json")
    CREDITS = URI("https://openrouter.ai/api/v1/credits").freeze
    ROOT = Rails.root.join("db/eval")

    module_function

    def run!(set:, calls:, cap:)
      request = JSON.parse(FIXTURE.read)
      body = { model: SystemOneAgent::OPENROUTER_MODEL, state: request["state"], questions: request["questions"] }
      send_all!(set: set, cap: cap, calls: Array.new(calls) { |index| [ { "call" => index + 1 }, body ] },
                kept: { "request_sha256" => Digest::SHA256.hexdigest(body.to_json) })
    end

    # EVERY ROOM, REPS TIMES, rooms in the file's order within each repetition
    # so a run stopped by the ceiling has spent evenly across the rooms.
    def run_rooms!(set:, reps:, cap:)
      rooms = JSON.parse(ROOMS.read)
      calls = (1..reps).flat_map do |rep|
        rooms.map do |room|
          [ { "room" => room["room"], "rep" => rep },
            { model: SystemOneAgent::OPENROUTER_MODEL, state: room["state"], questions: room["questions"] } ]
        end
      end
      calls.each_with_index { |(label, _), index| label["call"] = index + 1 }
      dir = send_all!(set: set, cap: cap, calls: calls,
                      kept: { "requests_file" => ROOMS.relative_path_from(Rails.root).to_s,
                              "requests_sha256" => Digest::SHA256.file(ROOMS).hexdigest, "reps" => reps })
      # The set carries the bytes it was measured on, so its summary never
      # reads a fixture that may have moved since.
      FileUtils.cp(ROOMS, dir.join("requests.json"))
      dir
    end

    def send_all!(set:, cap:, calls:, kept:)
      dir = ROOT.join(set)
      abort "#{dir} exists; a kept set is never written over" if dir.exist?
      key = ENV["OPENROUTER_API_KEY"].presence or abort "OPENROUTER_API_KEY is not set"

      receipts = []
      before = credits(key)
      spent = 0.0

      calls.each do |label, body|
        dearest = receipts.map { |r| r["cost"].to_f }.max || 0.0
        if spent + dearest > cap
          puts "stopped before call #{label["call"]}: #{spent.round(6)} spent + #{dearest} would cross #{cap}"
          break
        end

        receipt = label.merge(post(key, body))
        receipts << receipt
        spent += receipt["cost"].to_f
        puts "call #{label["call"]} #{label["room"]}: #{receipt["status"]} cost=#{receipt["cost"].inspect} spent=#{spent.round(6)}"
        break unless receipt["status"] == 200
        next if receipt["cost"].is_a?(Numeric)

        puts "stopped: call #{label["call"]} came back without usage.cost, so the ceiling cannot be kept"
        break
      end

      dir.mkpath
      File.write(dir.join("receipts.json"), "#{JSON.pretty_generate(
        "model" => SystemOneAgent::OPENROUTER_MODEL, "endpoint" => SystemOneAgent::OPENROUTER_ENDPOINT.to_s,
        **kept, "cap_usd" => cap,
        "credits_before" => before, "credits_after" => credits(key), "receipts" => receipts
      )}\n")
      dir
    end

    # The figures a kept set supports, recomputed from its file alone.
    def price(set, project: 48)
      kept = JSON.parse(ROOT.join(set, "receipts.json").read)
      costs = kept["receipts"].select { |r| r["status"] == 200 }.map { |r| r["cost"].to_f }
      per_call = costs.empty? ? nil : costs.sum / costs.size
      { "calls" => kept["receipts"].size, "succeeded" => costs.size, "receipt_total" => costs.sum,
        "per_call" => per_call, "projected_calls" => project,
        "projected" => per_call && per_call * project,
        "credit_delta" => kept.dig("credits_after", "total_usage").to_f - kept.dig("credits_before", "total_usage").to_f }
    end

    def post(key, body)
      endpoint = SystemOneAgent::OPENROUTER_ENDPOINT
      http_request = Net::HTTP::Post.new(endpoint)
      http_request["Authorization"] = "Bearer #{key}"
      http_request["Content-Type"] = "application/json"
      http_request.body = body.to_json
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Net::HTTP.start(endpoint.hostname, endpoint.port, use_ssl: true, read_timeout: 30) { |h| h.request(http_request) }
      seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)

      return { "status" => response.code.to_i, "seconds" => seconds, "error_body" => response.body } unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      { "status" => 200, "seconds" => seconds, "id" => payload["id"], "provider" => payload["provider"],
        "usage" => payload["usage"], "cost" => payload.dig("usage", "cost"), "answers" => payload["answers"] }
    end

    def credits(key)
      request = Net::HTTP::Get.new(CREDITS)
      request["Authorization"] = "Bearer #{key}"
      response = Net::HTTP.start(CREDITS.hostname, CREDITS.port, use_ssl: true) { |h| h.request(request) }
      JSON.parse(response.body)["data"]
    end
  end
end
