# SOMEBODY INVITED TO PLAY OVER THE API, and the only thing the API knows
# about them.
#
# There is no signup and no password. The maintainer runs
# `rake players:invite[name]`, which prints a token exactly once; this row keeps
# only its SHA-256 digest, so a copy of the database cannot be replayed as a
# login. A token is 32 random bytes, which is why a fast digest is enough here
# where a password would need a slow one: there is nothing to guess.
#
# A player reaches only their own playthroughs (`playthroughs.player_id`);
# worlds stay shared, and a room a player's turn realizes joins the world like
# any other. What a player may spend is `monthly_limit_usd`, enforced by
# `Player::Allowance` before a turn is accepted and before a call through the
# model relay (`Relay`) is forwarded -- the same token opens both. Revoking
# keeps the row and its receipts -- spend already metered must stay on the
# books -- and stops the token authenticating.
class Player < ApplicationRecord
  DEFAULT_MONTHLY_LIMIT_USD = BigDecimal("1")

  has_many :playthroughs, dependent: :restrict_with_exception
  has_many :chats, dependent: :restrict_with_exception
  has_many :system_one_receipts, dependent: :restrict_with_exception
  has_many :relay_receipts, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: true
  validates :token_digest, presence: true, uniqueness: true
  validates :monthly_limit_usd, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

  # A new player and their token. The token is returned here and nowhere else:
  # it is not stored, not logged and cannot be recovered, only replaced.
  def self.invite!(name, monthly_limit_usd: DEFAULT_MONTHLY_LIMIT_USD)
    token = SecureRandom.urlsafe_base64(32)
    player = create!(name: name, token_digest: digest(token), monthly_limit_usd: monthly_limit_usd)
    [ player, token ]
  end

  # The active player a presented token belongs to, or nil. The row is found by
  # its digest and the digest is then compared in constant time, so neither
  # the lookup nor the comparison says how much of a wrong token was right.
  def self.authenticate(token)
    return nil if token.blank?

    presented = digest(token)
    player = active.find_by(token_digest: presented)
    player if player && ActiveSupport::SecurityUtils.secure_compare(player.token_digest, presented)
  end

  def revoked? = revoked_at.present?

  def revoke!(at: Time.current) = update!(revoked_at: at)

  def allowance(now: Time.current) = Player::Allowance.new(self, now: now)
end
