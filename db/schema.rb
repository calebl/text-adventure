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

ActiveRecord::Schema[8.1].define(version: 2026_09_05_090100) do
  create_table "characters", force: :cascade do |t|
    t.integer "age"
    t.text "appearance"
    t.text "backstory"
    t.datetime "created_at", null: false
    t.boolean "deliberately_absent", default: false, null: false
    t.text "dislikes"
    t.text "fears"
    t.string "fullname"
    t.integer "hit_die"
    t.boolean "is_companion"
    t.boolean "is_protagonist", default: false, null: false
    t.integer "level"
    t.text "likes"
    t.integer "location_id"
    t.string "nickname"
    t.text "personality"
    t.integer "race_id", null: false
    t.string "sex"
    t.integer "story_id", null: false
    t.datetime "updated_at", null: false
    t.index "story_id, LOWER(fullname)", name: "index_characters_on_story_id_and_lower_fullname", unique: true
    t.index ["location_id", "id"], name: "index_characters_on_location_id_and_id"
    t.index ["location_id"], name: "index_characters_on_location_id"
    t.index ["race_id"], name: "index_characters_on_race_id"
    t.index ["story_id", "is_protagonist"], name: "index_characters_on_story_id_and_is_protagonist"
    t.index ["story_id"], name: "index_characters_on_story_id"
  end

  create_table "characters_scenes", id: false, force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "scene_id", null: false
    t.index ["character_id", "scene_id"], name: "index_characters_scenes_on_character_id_and_scene_id"
    t.index ["scene_id", "character_id"], name: "index_characters_scenes_on_scene_id_and_character_id"
  end

  create_table "chats", force: :cascade do |t|
    t.integer "character_id"
    t.datetime "created_at", null: false
    t.integer "model_id"
    t.string "model_id_string"
    t.integer "playthrough_id"
    t.string "purpose"
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_chats_on_character_id"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["playthrough_id", "character_id", "purpose"], name: "index_chats_on_conversation_key"
    t.index ["playthrough_id"], name: "index_chats_on_playthrough_id"
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
    t.integer "character_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "inscription"
    t.integer "location_id"
    t.string "name"
    t.integer "playthrough_id"
    t.text "properties"
    t.boolean "readable", default: false, null: false
    t.integer "template_id"
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_items_on_character_id"
    t.index ["location_id", "character_id"], name: "index_items_on_location_id_and_character_id"
    t.index ["location_id"], name: "index_items_on_location_id"
    t.index ["playthrough_id", "id"], name: "index_items_on_playthrough_id_and_id"
    t.index ["playthrough_id", "template_id"], name: "index_items_on_playthrough_id_and_template_id"
    t.index ["playthrough_id"], name: "index_items_on_playthrough_id"
    t.index ["template_id"], name: "index_items_on_template_id"
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
    t.string "detail_level", default: "stub", null: false
    t.datetime "last_protagonist_visit"
    t.text "lore"
    t.boolean "mobile", default: false, null: false
    t.string "name"
    t.integer "parent_location_id"
    t.integer "story_id", null: false
    t.text "teaser"
    t.datetime "updated_at", null: false
    t.index ["parent_location_id"], name: "index_locations_on_parent_location_id"
    t.index ["story_id", "detail_level"], name: "index_locations_on_story_id_and_detail_level"
    t.index ["story_id"], name: "index_locations_on_story_id"
  end

  create_table "locations_world_events", id: false, force: :cascade do |t|
    t.integer "location_id", null: false
    t.integer "world_event_id", null: false
    t.index ["location_id"], name: "index_locations_world_events_on_location_id"
    t.index ["world_event_id", "location_id"], name: "index_locations_world_events_on_world_event_id_and_location_id", unique: true
    t.index ["world_event_id"], name: "index_locations_world_events_on_world_event_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.integer "model_id"
    t.string "model_id_string"
    t.integer "output_tokens"
    t.string "role"
    t.integer "scene_id"
    t.integer "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["scene_id"], name: "index_messages_on_scene_id"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_models_on_family"
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "playthrough_drifts", force: :cascade do |t|
    t.string "action", null: false
    t.text "command", null: false
    t.datetime "created_at", null: false
    t.integer "location_id"
    t.text "offered"
    t.integer "playthrough_id", null: false
    t.integer "scene_id"
    t.datetime "story_timestamp"
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_playthrough_drifts_on_action"
    t.index ["location_id"], name: "index_playthrough_drifts_on_location_id"
    t.index ["playthrough_id", "story_timestamp"], name: "index_playthrough_drifts_on_playthrough_id_and_story_timestamp"
    t.index ["playthrough_id"], name: "index_playthrough_drifts_on_playthrough_id"
    t.index ["scene_id"], name: "index_playthrough_drifts_on_scene_id"
  end

  create_table "playthrough_feedbacks", force: :cascade do |t|
    t.text "answering_models"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.text "note"
    t.integer "output_tokens"
    t.integer "playthrough_id", null: false
    t.string "prose_model"
    t.text "prose_models"
    t.string "prose_purpose"
    t.integer "scene_id", null: false
    t.datetime "updated_at", null: false
    t.string "verdict", null: false
    t.index ["playthrough_id", "scene_id"], name: "index_playthrough_feedbacks_on_playthrough_id_and_scene_id", unique: true
    t.index ["playthrough_id"], name: "index_playthrough_feedbacks_on_playthrough_id"
    t.index ["prose_model"], name: "index_playthrough_feedbacks_on_prose_model"
    t.index ["scene_id"], name: "index_playthrough_feedbacks_on_scene_id"
    t.index ["verdict"], name: "index_playthrough_feedbacks_on_verdict"
  end

  create_table "playthrough_overreaches", force: :cascade do |t|
    t.text "acted", null: false
    t.string "action", null: false
    t.text "command", null: false
    t.datetime "created_at", null: false
    t.integer "location_id"
    t.integer "playthrough_id", null: false
    t.integer "scene_id"
    t.datetime "story_timestamp"
    t.text "unacted", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_playthrough_overreaches_on_action"
    t.index ["location_id"], name: "index_playthrough_overreaches_on_location_id"
    t.index ["playthrough_id", "story_timestamp"], name: "idx_on_playthrough_id_story_timestamp_b54cd36315"
    t.index ["playthrough_id"], name: "index_playthrough_overreaches_on_playthrough_id"
    t.index ["scene_id"], name: "index_playthrough_overreaches_on_scene_id"
  end

  create_table "playthrough_vitals", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "hp_current", null: false
    t.integer "playthrough_id", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_playthrough_vitals_on_character_id"
    t.index ["playthrough_id", "character_id"], name: "index_playthrough_vitals_on_playthrough_and_character", unique: true
    t.index ["playthrough_id"], name: "index_playthrough_vitals_on_playthrough_id"
  end

  create_table "playthroughs", force: :cascade do |t|
    t.integer "character_id"
    t.datetime "created_at", null: false
    t.integer "current_location_id"
    t.integer "current_scene_id"
    t.datetime "ended_at"
    t.integer "story_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_playthroughs_on_character_id"
    t.index ["current_location_id"], name: "index_playthroughs_on_current_location_id"
    t.index ["current_scene_id"], name: "index_playthroughs_on_current_scene_id"
    t.index ["story_id"], name: "index_playthroughs_on_story_id"
    t.index ["token"], name: "index_playthroughs_on_token", unique: true
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
    t.integer "acted_on_id"
    t.string "acted_on_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_opening", default: false, null: false
    t.integer "location_id", null: false
    t.integer "previous_scene_id"
    t.string "resolved_action"
    t.integer "story_id", null: false
    t.datetime "story_timestamp"
    t.text "summary"
    t.text "typed"
    t.datetime "updated_at", null: false
    t.index ["acted_on_type", "acted_on_id"], name: "index_scenes_on_acted_on"
    t.index ["location_id"], name: "index_scenes_on_location_id"
    t.index ["previous_scene_id"], name: "index_scenes_on_previous_scene_id"
    t.index ["story_id", "is_opening"], name: "index_scenes_on_story_id_and_is_opening"
    t.index ["story_id", "resolved_action"], name: "index_scenes_on_story_id_and_resolved_action"
    t.index ["story_id", "story_timestamp"], name: "index_scenes_on_story_id_and_story_timestamp"
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

  create_table "world_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "occurred_at", null: false
    t.integer "story_id", null: false
    t.text "summary", null: false
    t.datetime "updated_at", null: false
    t.integer "world_mechanic_id", null: false
    t.index ["story_id", "occurred_at"], name: "index_world_events_on_story_id_and_occurred_at"
    t.index ["story_id"], name: "index_world_events_on_story_id"
    t.index ["world_mechanic_id"], name: "index_world_events_on_world_mechanic_id"
  end

  create_table "world_mechanics", force: :cascade do |t|
    t.string "cadence", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "kind", null: false
    t.datetime "last_run_at"
    t.string "name", null: false
    t.integer "story_id", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id", "name"], name: "index_world_mechanics_on_story_id_and_name", unique: true
    t.index ["story_id"], name: "index_world_mechanics_on_story_id"
  end

  add_foreign_key "characters", "locations"
  add_foreign_key "characters", "races"
  add_foreign_key "characters", "stories"
  add_foreign_key "chats", "characters"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "playthroughs"
  add_foreign_key "interactions", "characters"
  add_foreign_key "interactions", "locations"
  add_foreign_key "interactions", "scenes"
  add_foreign_key "items", "characters"
  add_foreign_key "items", "locations"
  add_foreign_key "items", "playthroughs"
  add_foreign_key "location_connections", "locations"
  add_foreign_key "location_connections", "locations", column: "connected_location_id"
  add_foreign_key "locations", "locations", column: "parent_location_id"
  add_foreign_key "locations", "stories"
  add_foreign_key "locations_world_events", "locations"
  add_foreign_key "locations_world_events", "world_events"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "scenes"
  add_foreign_key "playthrough_drifts", "locations"
  add_foreign_key "playthrough_drifts", "playthroughs"
  add_foreign_key "playthrough_drifts", "scenes"
  add_foreign_key "playthrough_feedbacks", "playthroughs"
  add_foreign_key "playthrough_feedbacks", "scenes"
  add_foreign_key "playthrough_overreaches", "locations"
  add_foreign_key "playthrough_overreaches", "playthroughs"
  add_foreign_key "playthrough_overreaches", "scenes"
  add_foreign_key "playthrough_vitals", "characters"
  add_foreign_key "playthrough_vitals", "playthroughs"
  add_foreign_key "playthroughs", "characters"
  add_foreign_key "playthroughs", "locations", column: "current_location_id"
  add_foreign_key "playthroughs", "scenes", column: "current_scene_id"
  add_foreign_key "playthroughs", "stories"
  add_foreign_key "races", "universes"
  add_foreign_key "scenes", "locations"
  add_foreign_key "scenes", "scenes", column: "previous_scene_id"
  add_foreign_key "scenes", "stories"
  add_foreign_key "stories", "universes"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "world_events", "stories"
  add_foreign_key "world_events", "world_mechanics"
  add_foreign_key "world_mechanics", "stories"
end
