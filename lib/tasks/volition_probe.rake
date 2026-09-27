# The typed volition call's price. `Eval::VolitionProbe` has the design; the
# first task spends and the second reads a kept set for free.
namespace :eval do
  desc "Send the pinned volition request CALLS times (default 4) under CAP USD (default 0.05). SET=<name> required"
  task volition_probe: :environment do
    set = ENV["SET"].presence or abort "SET=<name> names the kept set under db/eval"
    dir = Eval::VolitionProbe.run!(set: set, calls: (ENV["CALLS"] || 4).to_i, cap: (ENV["CAP"] || 0.05).to_f)
    puts "kept #{dir.relative_path_from(Rails.root)}"
    puts JSON.pretty_generate(Eval::VolitionProbe.price(set))
  end

  desc "Per-call price and a projection from a kept volition probe set. SET=<name> PROJECT=48"
  task volition_probe_price: :environment do
    set = ENV["SET"].presence or abort "SET=<name> names the kept set under db/eval"
    puts JSON.pretty_generate(Eval::VolitionProbe.price(set, project: (ENV["PROJECT"] || 48).to_i))
  end
end
