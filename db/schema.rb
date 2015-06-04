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

ActiveRecord::Schema.define(version: 20150604140643) do

  create_table "alerts", force: :cascade do |t|
    t.integer  "system_id"
    t.integer  "service_id"
    t.integer  "criticality"
    t.datetime "generated"
    t.boolean  "closed"
    t.text     "description"
    t.string   "short_description", limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "alerts_events", id: false, force: :cascade do |t|
    t.integer "alert_id"
    t.integer "event_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text     "message"
    t.integer  "user_id"
    t.integer  "alert_id"
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
    t.integer  "system_id"
    t.integer  "service_id"
    t.datetime "generated"
    t.datetime "stored"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "events", ["generated"], name: "index_events_on_generated"

  create_table "events_words", id: false, force: :cascade do |t|
    t.integer  "event_id",  null: false
    t.integer  "word_id",   null: false
    t.datetime "generated"
  end

  add_index "events_words", ["event_id"], name: "index_events_words_on_event_id"
  add_index "events_words", ["generated"], name: "index_events_words_on_generated"
  add_index "events_words", ["word_id"], name: "index_events_words_on_word_id"

  create_table "jobs", force: :cascade do |t|
    t.string   "name",          limit: 255
    t.text     "description"
    t.integer  "user_id"
    t.text     "script"
    t.integer  "last_event_id"
    t.datetime "last_run"
    t.datetime "next_run"
    t.integer  "frequency"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "positions", force: :cascade do |t|
    t.integer  "word_id"
    t.integer  "position"
    t.integer  "event_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "positions", ["event_id"], name: "index_positions_on_event_id"
  add_index "positions", ["word_id"], name: "index_positions_on_word_id"

  create_table "rights", force: :cascade do |t|
    t.string "name",        limit: 255
    t.string "description", limit: 255
  end

  create_table "rights_roles", force: :cascade do |t|
    t.integer "right_id"
    t.integer "role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name",        limit: 255
    t.string "description", limit: 255
  end

  create_table "roles_users", force: :cascade do |t|
    t.integer "role_id"
    t.integer "user_id"
  end

  create_table "searches", force: :cascade do |t|
    t.text     "string"
    t.integer  "user_id"
    t.text     "description"
    t.string   "short_description", limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "services", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.text     "description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.string   "session_hash", limit: 255
    t.integer  "user_id"
    t.datetime "expiry"
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "statistics", force: :cascade do |t|
    t.integer  "type_id"
    t.datetime "timestamp"
    t.integer  "system_id"
    t.integer  "service_id"
    t.float    "stat"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "systems", force: :cascade do |t|
    t.string   "address",       limit: 255
    t.string   "name",          limit: 255
    t.text     "description"
    t.string   "administrator", limit: 255
    t.string   "contact_email", limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "monitor"
  end

  create_table "users", force: :cascade do |t|
    t.string   "username",     limit: 255
    t.string   "password",     limit: 255
    t.string   "first",        limit: 255
    t.string   "last",         limit: 255
    t.integer  "attempts"
    t.datetime "last_attempt"
    t.datetime "lastlogon"
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "words", force: :cascade do |t|
    t.text     "text",       limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "words", ["text"], name: "index_words_on_text"

end
