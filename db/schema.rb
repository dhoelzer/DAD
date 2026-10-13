# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160922164301) do

  create_table "alerts", force: :cascade do |t|
    t.integer  "system_id",         limit: 8
    t.integer  "service_id",        limit: 8
    t.integer  "criticality"
    t.datetime "generated"
    t.boolean  "closed"
    t.text     "description"
    t.string   "short_description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "alerts_events", id: false, force: :cascade do |t|
    t.integer "alert_id", limit: 8
    t.integer "event_id", limit: 8
  end

  add_index "alerts_events", ["alert_id"], name: "index_alerts_events_on_alert_id"

  create_table "comments", force: :cascade do |t|
    t.text     "message"
    t.integer  "user_id",    limit: 8
    t.integer  "alert_id",   limit: 8
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "displays", force: :cascade do |t|
    t.string   "key"
    t.string   "name"
    t.text     "description"
    t.text     "display_script"
    t.integer  "user_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "events", force: :cascade do |t|
    t.integer  "system_id",  limit: 8
    t.integer  "service_id", limit: 8
    t.datetime "generated",            default: '2026-10-13 20:38:49', null: false
    t.datetime "stored"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "hunks"
  end

  add_index "events", ["generated"], name: "index_events_on_generated"

  create_table "events_words", id: false, force: :cascade do |t|
    t.integer  "event_id",  limit: 8
    t.integer  "word_id",   limit: 8
    t.datetime "generated",           default: '2026-10-13 20:38:49', null: false
  end

  add_index "events_words", ["generated"], name: "index_events_words_on_generated"

  create_table "exclusions", force: :cascade do |t|
    t.string   "pattern"
    t.integer  "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "hunks", force: :cascade do |t|
    t.string   "text",       limit: 32
    t.datetime "created_at",            null: false
    t.datetime "updated_at",            null: false
  end

  add_index "hunks", ["text"], name: "index_hunks_on_text"

  create_table "jobs", force: :cascade do |t|
    t.string   "name"
    t.text     "description"
    t.integer  "user_id",       limit: 8
    t.text     "script"
    t.integer  "last_event_id", limit: 8
    t.datetime "last_run"
    t.datetime "next_run"
    t.integer  "frequency"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "preferences", force: :cascade do |t|
    t.integer  "user_id"
    t.integer  "liveEventsDisplayed"
    t.string   "dashboardElements"
    t.datetime "created_at",          null: false
    t.datetime "updated_at",          null: false
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
    t.text     "string"
    t.integer  "user_id",           limit: 8
    t.text     "description"
    t.string   "short_description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "services", force: :cascade do |t|
    t.string   "name"
    t.text     "description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.string   "session_hash"
    t.integer  "user_id"
    t.datetime "expiry"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

  create_table "statistics", force: :cascade do |t|
    t.integer  "type_id"
    t.datetime "timestamp"
    t.integer  "system_id",  limit: 8
    t.integer  "service_id", limit: 8
    t.float    "stat"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "systems", force: :cascade do |t|
    t.string   "address"
    t.string   "name"
    t.text     "description"
    t.string   "administrator"
    t.string   "contact_email"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "monitor"
  end

  create_table "users", force: :cascade do |t|
    t.string   "username"
    t.string   "password"
    t.string   "first"
    t.string   "last"
    t.integer  "attempts"
    t.datetime "last_attempt"
    t.datetime "lastlogon"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

  create_table "words", force: :cascade do |t|
    t.string "text"
  end

  add_index "words", ["text"], name: "index_words_on_text"

end
