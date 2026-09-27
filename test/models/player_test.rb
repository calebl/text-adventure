require "test_helper"

class PlayerTest < ActiveSupport::TestCase
  test "an invitation stores the digest and returns the token only once" do
    player, token = Player.invite!("Ada")

    assert_operator token.length, :>=, 40
    assert_equal Player.digest(token), player.token_digest
    assert_not_includes player.attributes.values.map(&:to_s), token, "the plain token is stored nowhere on the row"
    assert_equal Player::DEFAULT_MONTHLY_LIMIT_USD, player.monthly_limit_usd
  end

  test "a token authenticates its player and nothing else does" do
    player, token = Player.invite!("Ada")
    other, = Player.invite!("Grace")

    assert_equal player, Player.authenticate(token)
    assert_nil Player.authenticate("#{token}x")
    assert_nil Player.authenticate(token[0..-2])
    assert_nil Player.authenticate("")
    assert_nil Player.authenticate(nil)
    assert_not_equal other, Player.authenticate(token)
  end

  test "a revoked token stops authenticating and the row is kept" do
    player, token = Player.invite!("Ada")
    player.revoke!

    assert_nil Player.authenticate(token)
    assert Player.exists?(player.id)
  end

  test "the comparison is constant time" do
    player, token = Player.invite!("Ada")
    compared = []
    ActiveSupport::SecurityUtils.stub(:secure_compare, ->(a, b) { compared << [ a, b ]; a == b }) do
      assert_equal player, Player.authenticate(token)
    end
    assert_equal [ [ player.token_digest, Player.digest(token) ] ], compared
  end

  test "names are unique" do
    create(:player, name: "Ada")
    assert_not build(:player, name: "Ada").valid?
  end
end
