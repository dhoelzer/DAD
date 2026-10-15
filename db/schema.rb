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

ActiveRecord::Schema[8.1].define(version: 2026_10_14_000001) do
  create_table "alerts", force: :cascade do |t|
    t.integer "system_id", limit: 8
    t.integer "service_id", limit: 8
    t.integer "criticality"
    t.datetime "generated", precision: nil
    t.boolean "closed"
    t.text "description"
    t.string "short_description"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "alerts_events", id: false, force: :cascade do |t|
    t.integer "alert_id", limit: 8
    t.integer "event_id", limit: 8
    t.index ["alert_id"], name: "index_alerts_events_on_alert_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "message"
    t.integer "user_id", limit: 8
    t.integer "alert_id", limit: 8
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "displays", force: :cascade do |t|
    t.string "key"
    t.string "name"
    t.text "description"
    t.text "display_script"
    t.integer "user_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "events", force: :cascade do |t|
    t.integer "system_id", limit: 8
    t.integer "service_id", limit: 8
    t.datetime "generated", precision: nil, null: false
    t.datetime "stored", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.text "hunks"
    t.index ["generated"], name: "index_events_on_generated"
  end

  create_table "events_words", id: false, force: :cascade do |t|
    t.integer "event_id", limit: 8
    t.integer "word_id", limit: 8
    t.datetime "generated", precision: nil, null: false
    t.index ["generated"], name: "index_events_words_on_generated"
    t.index ["word_id", "generated", "event_id"], name: "index_events_words_on_word_id_and_generated_and_event_id"
  end

  create_table "exclusions", force: :cascade do |t|
    t.string "pattern"
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "hunks", force: :cascade do |t|
    t.string "text", limit: 32
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["text"], name: "index_hunks_on_text"
  end

  create_table "jobs", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "user_id", limit: 8
    t.text "script"
    t.integer "last_event_id", limit: 8
    t.datetime "last_run", precision: nil
    t.datetime "next_run", precision: nil
    t.integer "frequency"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "preferences", force: :cascade do |t|
    t.integer "user_id"
    t.integer "liveEventsDisplayed"
    t.string "dashboardElements"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "rights", force: :cascade do |t|
    t.string "name"
    t.string "description"
  end

  create_table "rights_roles", force: :cascade do |t|
    t.integer "right_id"
    t.integer "role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "description"
  end

  create_table "roles_users", force: :cascade do |t|
    t.integer "role_id"
    t.integer "user_id"
  end

  create_table "searches", force: :cascade do |t|
    t.text "string"
    t.integer "user_id", limit: 8
    t.text "description"
    t.string "short_description"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "services", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "sessions", force: :cascade do |t|
    t.string "session_hash"
    t.integer "user_id"
    t.datetime "expiry", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "statistics", force: :cascade do |t|
    t.integer "type_id"
    t.datetime "timestamp", precision: nil
    t.integer "system_id", limit: 8
    t.integer "service_id", limit: 8
    t.float "stat"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "systems", force: :cascade do |t|
    t.string "address"
    t.string "name"
    t.text "description"
    t.string "administrator"
    t.string "contact_email"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "monitor"
  end

  create_table "users", force: :cascade do |t|
    t.string "username"
    t.string "password"
    t.string "first"
    t.string "last"
    t.integer "attempts"
    t.datetime "last_attempt", precision: nil
    t.datetime "lastlogon", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "words", force: :cascade do |t|
    t.string "text"
    t.index ["text"], name: "index_words_on_text"
  end
end
