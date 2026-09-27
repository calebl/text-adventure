FactoryBot.define do
  factory :player do
    sequence(:name) { |number| "player-#{number}" }
    # A fixed-shape token per row, so a test can present it: `token` is not a
    # column, only the digest is stored.
    transient { token { "test-token-#{name}" } }
    token_digest { Player.digest(token) }
    monthly_limit_usd { Player::DEFAULT_MONTHLY_LIMIT_USD }

    trait :revoked do
      revoked_at { Time.utc(2026, 9, 1) }
    end
  end
end
