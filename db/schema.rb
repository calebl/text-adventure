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

ActiveRecord::Schema[8.0].define(version: 2025_08_24_193519) do
  create_table "characters", force: :cascade do |t|
    t.integer "story_id", null: false
    t.string "fullname"
    t.string "nickname"
    t.integer "age"
    t.string "sex"
    t.string "race"
    t.text "personality"
    t.text "appearance"
    t.text "likes"
    t.text "dislikes"
    t.text "fears"
    t.text "backstory"
    t.boolean "is_companion"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id"], name: "index_characters_on_story_id"
  end

  create_table "characters_scenes", id: false, force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "scene_id", null: false
    t.index ["character_id", "scene_id"], name: "index_characters_scenes_on_character_id_and_scene_id"
    t.index ["scene_id", "character_id"], name: "index_characters_scenes_on_scene_id_and_character_id"
  end

  create_table "chats", force: :cascade do |t|
    t.string "model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "interactions", force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "scene_id"
    t.integer "location_id"
    t.text "pre_thought"
    t.text "pre_feeling"
    t.text "action"
    t.text "post_feeling"
    t.text "post_thought"
    t.text "inner_resolution"
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "user_input"
    t.index ["character_id"], name: "index_interactions_on_character_id"
    t.index ["location_id"], name: "index_interactions_on_location_id"
    t.index ["scene_id"], name: "index_interactions_on_scene_id"
  end

  create_table "items", force: :cascade do |t|
    t.integer "character_id", null: false
    t.string "name"
    t.text "description"
    t.text "properties"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_items_on_character_id"
  end

  create_table "location_connections", force: :cascade do |t|
    t.integer "location_id", null: false
    t.integer "connected_location_id", null: false
    t.text "distance"
    t.text "time_to_travel"
    t.text "travel_method"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connected_location_id"], name: "index_location_connections_on_connected_location_id"
    t.index ["location_id", "connected_location_id"], name: "idx_on_location_id_connected_location_id_a0efda2bf6", unique: true
    t.index ["location_id"], name: "index_location_connections_on_location_id"
  end

  create_table "locations", force: :cascade do |t|
    t.integer "story_id", null: false
    t.string "name"
    t.text "description"
    t.text "lore"
    t.datetime "last_protagonist_visit"
    t.integer "parent_location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_location_id"], name: "index_locations_on_parent_location_id"
    t.index ["story_id"], name: "index_locations_on_story_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.string "role"
    t.text "content"
    t.string "model_id"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "tool_call_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "scenes", force: :cascade do |t|
    t.integer "story_id", null: false
    t.integer "location_id", null: false
    t.integer "previous_scene_id"
    t.text "description"
    t.datetime "story_timestamp"
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_scenes_on_location_id"
    t.index ["previous_scene_id"], name: "index_scenes_on_previous_scene_id"
    t.index ["story_id"], name: "index_scenes_on_story_id"
  end

  create_table "stories", force: :cascade do |t|
    t.string "title"
    t.string "genre"
    t.text "preface"
    t.text "summary"
    t.datetime "start_time"
    t.integer "universe_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["universe_id"], name: "index_stories_on_universe_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.integer "message_id", null: false
    t.string "tool_call_id", null: false
    t.string "name", null: false
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id"
  end

  create_table "universes", force: :cascade do |t|
    t.text "physics"
    t.text "technology"
    t.text "weapons"
    t.text "races"
    t.text "civilizations"
    t.text "geographies"
    t.text "history"
    t.text "economics"
    t.text "politics"
    t.text "religion"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

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
  add_foreign_key "scenes", "locations"
  add_foreign_key "scenes", "scenes", column: "previous_scene_id"
  add_foreign_key "scenes", "stories"
  add_foreign_key "stories", "universes"
  add_foreign_key "tool_calls", "messages"
end
