require "test_helper"

# What one call has to produce to open a story: the four story columns, plus
# the name and teaser of the room the preface drops the player into.
#
# The opening room lives here rather than in a schema of its own because the
# same call already wrote the preface describing it. Splitting it cost a whole
# extra round trip to produce two short strings.
class Story::SchemaTest < ActiveSupport::TestCase
  include SchemaAssertions

  SCHEMA = Story::Schema

  STORY_FIELDS = %w[title genre preface summary].freeze
  OPENING_FIELDS = %w[opening_location_name opening_location_teaser].freeze

  test "describes the story fields and the opening room, in order" do
    assert_equal STORY_FIELDS + OPENING_FIELDS, schema_properties(SCHEMA).keys
  end

  test "every field is required" do
    assert_equal STORY_FIELDS + OPENING_FIELDS, schema_required(SCHEMA)
  end

  test "forbids fields nothing downstream reads" do
    assert_equal false, json_schema_body(SCHEMA)["additionalProperties"]
  end

  test "every field is described" do
    assert_every_field_described(SCHEMA)
  end

  # The preface and summary are interpolated into every location generated for
  # this story, so an unbounded one costs context on every room ever built.
  test "every field carries an explicit max_length" do
    schema_properties(SCHEMA).each do |name, property|
      assert property["maxLength"].present?, "#{SCHEMA}##{name} needs a max_length"
    end
  end

  test "every field states its length in words, sentences or paragraphs" do
    schema_properties(SCHEMA).each do |name, property|
      assert_match(/word|sentence|paragraph/i, property["description"],
                   "#{SCHEMA}##{name} needs a stated length")
    end
  end

  test "the story fields are bounded to their column shapes" do
    assert_schema_field(SCHEMA, :title, type: :string, maxLength: 80)
    assert_schema_field(SCHEMA, :genre, type: :string, maxLength: 60)
    assert_schema_field(SCHEMA, :preface, type: :string, maxLength: 1800)
    assert_schema_field(SCHEMA, :summary, type: :string, maxLength: 900)
  end

  # These two make a Location stub, so they are bounded exactly as a stub's own
  # columns are: a short name and a single line.
  test "the opening room is bounded to what a stub is made of" do
    assert_schema_field(SCHEMA, :opening_location_name, type: :string, maxLength: 60)
    assert_schema_field(SCHEMA, :opening_location_teaser, type: :string, maxLength: 160)
  end

  test "the story fields map to story columns" do
    assert_equal [], STORY_FIELDS - Story.column_names
  end

  # Story::Generator builds a stub Location out of these two, so they have to be
  # everything a stub is validated on.
  test "the opening fields fill everything a stub is validated on" do
    assert build(:location, :stub).valid?
  end

  # Everything Story validates on either comes from this schema or is set by
  # the generator, so a story cannot come back from one call still invalid.
  test "fills every story column the record is validated on, except start_time" do
    story = Story.new(universe: build(:universe))
    story.valid?

    assert_equal [ "start_time" ], story.errors.attribute_names.map(&:to_s) - STORY_FIELDS
  end
end
