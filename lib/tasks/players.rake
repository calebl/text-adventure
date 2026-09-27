# INVITED PLAYERS FOR THE ENGINE API. See `Player` for what a player is and
# `Player::Allowance` for what they may spend. No signup exists anywhere: a
# player is whoever the maintainer has run `invite` for.
namespace :players do
  desc "Invite a player and print their token ONCE: rake players:invite[name] (LIMIT_USD=1 by default)"
  task :invite, [ :name ] => :environment do |_task, args|
    name = args[:name].to_s.strip
    abort "Name the player: rake players:invite[name]" if name.empty?

    limit = ENV["LIMIT_USD"].presence || Player::DEFAULT_MONTHLY_LIMIT_USD
    player, token = Player.invite!(name, monthly_limit_usd: BigDecimal(limit.to_s))
    puts "Invited #{player.name}, limit $#{format("%.2f", player.monthly_limit_usd)} a month."
    puts "Their token, shown this once and stored nowhere -- send it to them privately:"
    puts
    puts "  #{token}"
  end

  desc "Revoke a player's token: rake players:revoke[name]. Their games and receipts are kept."
  task :revoke, [ :name ] => :environment do |_task, args|
    player = Player.find_by(name: args[:name].to_s.strip) or abort "No player named #{args[:name].inspect}."
    player.revoke!
    puts "Revoked #{player.name}. Their token no longer authenticates."
  end

  desc "Set a player's monthly limit in US dollars: rake players:limit[name,2.50]"
  task :limit, [ :name, :usd ] => :environment do |_task, args|
    player = Player.find_by(name: args[:name].to_s.strip) or abort "No player named #{args[:name].inspect}."
    usd = BigDecimal(args[:usd].to_s, exception: false)
    abort "Give the limit in dollars: rake players:limit[name,2.50]" if usd.nil? || usd.negative?

    player.update!(monthly_limit_usd: usd)
    allowance = player.allowance
    puts format("%s: limit $%.2f a month, $%.2f used so far this month.", player.name, usd, allowance.spent)
  end
end
