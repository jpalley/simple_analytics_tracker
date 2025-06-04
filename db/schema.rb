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

ActiveRecord::Schema[8.0].define(version: 2025_06_02_012445) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "error_logs", force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "notification_sent", default: false
  end

  create_table "error_requests", force: :cascade do |t|
    t.integer "status_code", null: false
    t.string "request_method", null: false
    t.string "path", null: false
    t.text "user_agent"
    t.string "ip_address"
    t.text "referer"
    t.text "error_message"
    t.text "request_params"
    t.datetime "timestamp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status_code", "timestamp"], name: "index_error_requests_on_status_code_and_timestamp"
    t.index ["status_code"], name: "index_error_requests_on_status_code"
    t.index ["timestamp"], name: "index_error_requests_on_timestamp"
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
    t.index ["synced"], name: "index_events_on_synced"
    t.index ["synced_at"], name: "index_events_on_synced_at"
    t.index ["uuid"], name: "index_events_on_uuid"
  end

  create_table "facebook_audience_sync_histories", force: :cascade do |t|
    t.integer "records_synced", default: 0
    t.text "error_message"
    t.bigint "facebook_audience_sync_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["facebook_audience_sync_id"], name: "idx_on_facebook_audience_sync_id_7a5c32f584"
  end

  create_table "facebook_audience_sync_users", force: :cascade do |t|
    t.bigint "facebook_audience_sync_id", null: false
    t.string "email_hash"
    t.string "phone_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hubspot_contact_id"
    t.index ["facebook_audience_sync_id", "hubspot_contact_id"], name: "index_fb_audience_sync_users_hubspot_unique", unique: true
    t.index ["facebook_audience_sync_id"], name: "idx_on_facebook_audience_sync_id_37c70ecead"
    t.index ["hubspot_contact_id"], name: "index_facebook_audience_sync_users_on_hubspot_contact_id"
  end

  create_table "facebook_audience_syncs", force: :cascade do |t|
    t.string "table_name", null: false
    t.string "audience_name", null: false
    t.string "facebook_audience_id"
    t.string "last_counter", default: "0"
    t.boolean "enabled", default: true
    t.boolean "test_mode", default: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_facebook_audience_syncs_on_enabled"
    t.index ["table_name"], name: "index_facebook_audience_syncs_on_table_name"
  end

  create_table "facebook_sync_histories", force: :cascade do |t|
    t.integer "conversions"
    t.bigint "facebook_sync_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["facebook_sync_id"], name: "index_facebook_sync_histories_on_facebook_sync_id"
  end

  create_table "facebook_syncs", force: :cascade do |t|
    t.string "table_name"
    t.string "event_name"
    t.string "event_value"
    t.string "last_counter"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_source_url"
    t.string "action_source"
    t.boolean "enabled", default: true
    t.boolean "test_mode", default: false
  end

  create_table "hourly_stats", force: :cascade do |t|
    t.datetime "hour", null: false
    t.integer "events_count", default: 0
    t.integer "unique_people_count", default: 0
    t.integer "new_people_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "error_4xx_count", default: 0
    t.integer "error_5xx_count", default: 0
    t.integer "error_400_count", default: 0
    t.integer "error_401_count", default: 0
    t.integer "error_403_count", default: 0
    t.integer "error_404_count", default: 0
    t.integer "error_422_count", default: 0
    t.integer "error_500_count", default: 0
    t.integer "error_502_count", default: 0
    t.integer "error_503_count", default: 0
    t.integer "total_requests_count", default: 0
    t.index ["hour"], name: "index_hourly_stats_on_hour", unique: true
  end

  create_table "hubspot_sync_statuses", force: :cascade do |t|
    t.string "object_type", null: false
    t.string "status", null: false
    t.integer "record_count"
    t.text "error_message"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["object_type"], name: "index_hubspot_sync_statuses_on_object_type"
    t.index ["status"], name: "index_hubspot_sync_statuses_on_status"
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
    t.index ["hubspot_synced_at"], name: "index_people_on_hubspot_synced_at"
    t.index ["synced"], name: "index_people_on_synced"
    t.index ["synced_at"], name: "index_people_on_synced_at"
  end

  add_foreign_key "events", "people", column: "uuid", primary_key: "uuid"
  add_foreign_key "facebook_audience_sync_histories", "facebook_audience_syncs"
  add_foreign_key "facebook_audience_sync_users", "facebook_audience_syncs"
end
