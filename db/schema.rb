# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_30_192215) do
  create_table "characters", force: :cascade do |t|
    t.integer "age"
    t.text "appearance"
    t.text "backstory"
    t.datetime "created_at", null: false
    t.text "dislikes"
    t.text "fears"
    t.string "fullname"
    t.boolean "is_companion"
    t.text "likes"
    t.string "nickname"
    t.text "personality"
    t.integer "race_id", null: false
    t.string "sex"
    t.integer "story_id", null: false
    t.datetime "updated_at", null: false
    t.index ["race_id"], name: "index_characters_on_race_id"
    t.index ["story_id"], name: "index_characters_on_story_id"
  end

  create_table "characters_scenes", id: false, force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "scene_id", null: false
    t.index ["character_id", "scene_id"], name: "index_characters_scenes_on_character_id_and_scene_id"
    t.index ["scene_id", "character_id"], name: "index_characters_scenes_on_scene_id_and_character_id"
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "model_id"
    t.datetime "updated_at", null: false
  end

  create_table "interactions", force: :cascade do |t|
    t.text "action"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.text "inner_resolution"
    t.integer "location_id"
    t.text "post_feeling"
    t.text "post_thought"
    t.text "pre_feeling"
    t.text "pre_thought"
    t.integer "scene_id"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.text "user_input"
    t.index ["character_id"], name: "index_interactions_on_character_id"
    t.index ["location_id"], name: "index_interactions_on_location_id"
    t.index ["scene_id"], name: "index_interactions_on_scene_id"
  end

  create_table "items", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.text "properties"
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_items_on_character_id"
  end

  create_table "location_connections", force: :cascade do |t|
    t.integer "connected_location_id", null: false
    t.datetime "created_at", null: false
    t.text "distance"
    t.integer "location_id", null: false
    t.text "time_to_travel"
    t.text "travel_method"
    t.datetime "updated_at", null: false
    t.index ["connected_location_id"], name: "index_location_connections_on_connected_location_id"
    t.index ["location_id", "connected_location_id"], name: "idx_on_location_id_connected_location_id_a0efda2bf6", unique: true
    t.index ["location_id"], name: "index_location_connections_on_location_id"
  end

  create_table "locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_protagonist_visit"
    t.text "lore"
    t.string "name"
    t.integer "parent_location_id"
    t.integer "story_id", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_location_id"], name: "index_locations_on_parent_location_id"
    t.index ["story_id"], name: "index_locations_on_story_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.string "model_id"
    t.integer "output_tokens"
    t.string "role"
    t.integer "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "races", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "name", null: false
    t.integer "universe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["universe_id", "name"], name: "index_races_on_universe_id_and_name", unique: true
    t.index ["universe_id"], name: "index_races_on_universe_id"
  end

  create_table "scenes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "location_id", null: false
    t.integer "previous_scene_id"
    t.integer "story_id", null: false
    t.datetime "story_timestamp"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_scenes_on_location_id"
    t.index ["previous_scene_id"], name: "index_scenes_on_previous_scene_id"
    t.index ["story_id"], name: "index_scenes_on_story_id"
  end

  create_table "stories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "genre"
    t.text "preface"
    t.datetime "start_time"
    t.text "summary"
    t.string "title"
    t.integer "universe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["universe_id"], name: "index_stories_on_universe_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.string "name", null: false
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id"
  end

  create_table "universes", force: :cascade do |t|
    t.text "civilizations"
    t.datetime "created_at", null: false
    t.text "economics"
    t.text "geographies"
    t.text "history"
    t.text "physics"
    t.text "politics"
    t.text "religion"
    t.text "technology"
    t.datetime "updated_at", null: false
    t.text "weapons"
  end

  add_foreign_key "characters", "races"
  add_foreign_key "characters", "stories"
  add_foreign_key "interactions", "characters"
  add_foreign_key "interactions", "locations"
  add_foreign_key "interactions", "scenes"
  add_foreign_key "items", "characters"
  add_foreign_key "location_connections", "locations"
  add_foreign_key "location_connections", "locations", column: "connected_location_id"
  add_foreign_key "locations", "locations", column: "parent_location_id"
  add_foreign_key "locations", "stories"
  add_foreign_key "messages", "chats"
  add_foreign_key "races", "universes"
  add_foreign_key "scenes", "locations"
  add_foreign_key "scenes", "scenes", column: "previous_scene_id"
  add_foreign_key "scenes", "stories"
  add_foreign_key "stories", "universes"
  add_foreign_key "tool_calls", "messages"
end
