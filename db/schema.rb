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

ActiveRecord::Schema[8.0].define(version: 2024_12_07_063252) do
  create_table "error_logs", force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "events", force: :cascade do |t|
    t.string "uuid"
    t.string "event_type"
    t.datetime "timestamp"
    t.json "event_data"
    t.boolean "synced", default: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["uuid"], name: "index_events_on_uuid"
  end

  create_table "facebook_sync_histories", force: :cascade do |t|
    t.integer "conversions"
    t.integer "facebook_sync_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["facebook_sync_id"], name: "index_facebook_sync_histories_on_facebook_sync_id"
  end

  create_table "facebook_syncs", force: :cascade do |t|
    t.boolean "enabled", default: true
    t.boolean "test_mode", default: false
    t.string "table_name"
    t.string "event_name"
    t.string "event_value"
    t.string "last_counter"
    t.string "event_source_url"
    t.string "action_source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "hourly_stats", force: :cascade do |t|
    t.datetime "hour", null: false
    t.integer "events_count", default: 0
    t.integer "unique_people_count", default: 0
    t.integer "new_people_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hour"], name: "index_hourly_stats_on_hour", unique: true
  end

  create_table "people", primary_key: "uuid", id: :string, force: :cascade do |t|
    t.json "initial_params"
    t.json "latest_params"
    t.json "properties", default: {}
    t.boolean "synced", default: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "hubspot_synced_at"
  end

  add_foreign_key "events", "people", column: "uuid", primary_key: "uuid"
end
