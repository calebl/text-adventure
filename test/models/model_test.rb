require "test_helper"

# RubyLLM's model registry, added by the v1.7 acts_as migration. Chats and
# messages point at a row here instead of storing a provider model string, and
# the registry is read out of this table rather than the gem's bundled
# models.json -- so an empty table means no model resolves at all.
class ModelTest < ActiveSupport::TestCase
  # RubyLLM memoizes the registry process-wide the first time anything resolves
  # a model, and tests build their registry rows inside transactions that roll
  # back. A snapshot that survives into the next test resolves that test's model
  # names against rows that no longer exist -- which shows up as a
  # ModelNotFoundError for a row the failing test just created, in whichever
  # parallel worker happened to run the two tests together. test_helper.rb drops
  # the memo before every test; this is the assertion that it still does.
  test "no registry snapshot leaks in from an earlier test" do
    assert_nil RubyLLM::Models.instance_variable_get(:@instance),
               "a memoized model registry survived into this test, so model resolution here depends on test order"
  end

  test "a model resolves against the rows this test created, not an earlier snapshot" do
    create(:model, :ollama)
    assert_equal [ "gemma3:12b" ], RubyLLM.models.all.map(&:id)
  end

  test "the factory builds a valid model" do
    assert_predicate build(:model), :valid?
  end

  test "requires a model id, provider and name" do
    model = Model.new

    assert_not_predicate model, :valid?
    assert_includes model.errors.attribute_names, :model_id
    assert_includes model.errors.attribute_names, :provider
    assert_includes model.errors.attribute_names, :name
  end

  # Built directly rather than through the factory: the factory deliberately
  # reuses an existing row, which is the opposite of what this asserts.
  test "a model id is unique within a provider" do
    create(:model, model_id: "minimax/minimax-m3", provider: "openrouter")
    duplicate = Model.new(model_id: "minimax/minimax-m3", provider: "openrouter", name: "MiniMax M3")

    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors.attribute_names, :model_id
  end

  test "the same model id may exist under a different provider" do
    create(:model, model_id: "minimax/minimax-m3", provider: "openrouter")

    assert_predicate build(:model, model_id: "minimax/minimax-m3", provider: "ollama"), :valid?
  end

  test "has many chats" do
    model = create(:model)
    chat = create(:chat, model: model)

    assert_equal [ chat ], model.chats.to_a
  end

  test "converts to a RubyLLM model info object" do
    model = create(:model, model_id: "minimax/minimax-m3", provider: "openrouter", context_window: 200_000)
    info = model.to_llm

    assert_equal "minimax/minimax-m3", info.id
    assert_equal "openrouter", info.provider
    assert_equal 200_000, info.context_window
  end

  # This is the footgun of the new registry: RubyLLM resolves model names out
  # of this table, and an empty table resolves nothing rather than falling back
  # to the gem's bundled models.json. `bin/rails ruby_llm:load_models` fills it.
  test "the registry RubyLLM reads is backed by this table" do
    assert_equal "Model", RubyLLM.config.model_registry_class

    create(:model, model_id: "vendor/only-in-the-database", provider: "openrouter", name: "Only Here")
    RubyLLM.models.load_from_database!

    assert_includes RubyLLM.models.all.map(&:id), "vendor/only-in-the-database"
  end
end
