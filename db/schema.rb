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

ActiveRecord::Schema[8.1].define(version: 2026_10_26_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_runs", force: :cascade do |t|
    t.bigint "work_item_id", null: false
    t.string "source", null: false
    t.string "external_id", null: false
    t.string "stage_type"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.decimal "cost_usd", precision: 12, scale: 6
    t.integer "tokens"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "external_id"], name: "index_agent_runs_on_source_and_external_id", unique: true
    t.index ["work_item_id"], name: "index_agent_runs_on_work_item_id"
  end

  create_table "attention_spans", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "work_item_id"
    t.bigint "batch_id"
    t.string "activity", null: false
    t.string "source", default: "heartbeat", null: false
    t.datetime "started_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_attention_spans_on_batch_id"
    t.index ["person_id", "started_at"], name: "index_attention_spans_on_person_id_and_started_at"
    t.index ["person_id"], name: "index_attention_spans_on_person_id"
    t.index ["work_item_id"], name: "index_attention_spans_on_work_item_id"
  end

  create_table "batches", force: :cascade do |t|
    t.string "source", null: false
    t.string "external_id", null: false
    t.string "label"
    t.bigint "started_by_id"
    t.datetime "started_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "external_id"], name: "index_batches_on_source_and_external_id", unique: true
    t.index ["started_by_id"], name: "index_batches_on_started_by_id"
  end

  create_table "harvest_projects", force: :cascade do |t|
    t.bigint "harvest_id", null: false
    t.string "name", null: false
    t.string "code"
    t.string "client_name"
    t.boolean "is_active", default: true, null: false
    t.jsonb "tasks", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["harvest_id"], name: "index_harvest_projects_on_harvest_id", unique: true
  end

  create_table "ledger_settings", force: :cascade do |t|
    t.string "split_rule", default: "agent_points", null: false
    t.integer "idle_gap_minutes", default: 3, null: false
    t.integer "rounding_minutes", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "harvest_account_name"
    t.bigint "harvest_user_id"
    t.string "harvest_user_name"
    t.string "harvest_user_email"
    t.boolean "harvest_timestamp_mode"
    t.datetime "harvest_checked_at"
    t.text "harvest_check_error"
    t.datetime "harvest_projects_synced_at"
    t.datetime "harvest_test_passed_at"
    t.jsonb "harvest_test_log", default: [], null: false
  end

  create_table "people", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.bigint "harvest_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_people_on_email", unique: true
  end

  create_table "pipeline_events", force: :cascade do |t|
    t.bigint "work_item_id", null: false
    t.bigint "person_id"
    t.string "source", null: false
    t.string "external_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_pipeline_events_on_person_id"
    t.index ["source", "external_id"], name: "index_pipeline_events_on_source_and_external_id", unique: true
    t.index ["work_item_id", "occurred_at"], name: "index_pipeline_events_on_work_item_id_and_occurred_at"
    t.index ["work_item_id"], name: "index_pipeline_events_on_work_item_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "repo", null: false
    t.string "name", null: false
    t.bigint "harvest_project_id"
    t.bigint "harvest_dev_task_id"
    t.bigint "harvest_qa_task_id"
    t.bigint "harvest_supervision_task_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repo"], name: "index_projects_on_repo", unique: true
  end

  create_table "time_drafts", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "work_item_id", null: false
    t.date "spent_on", null: false
    t.string "activity", null: false
    t.integer "direct_seconds", default: 0, null: false
    t.integer "overhead_seconds", default: 0, null: false
    t.decimal "hours", precision: 6, scale: 2, null: false
    t.text "notes"
    t.string "status", default: "draft", null: false
    t.bigint "harvest_time_entry_id"
    t.datetime "sent_at"
    t.text "last_error"
    t.jsonb "last_payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "harvest_verified_at"
    t.text "harvest_verify_note"
    t.index ["person_id", "work_item_id", "spent_on", "activity"], name: "index_time_drafts_uniqueness", unique: true
    t.index ["person_id"], name: "index_time_drafts_on_person_id"
    t.index ["work_item_id"], name: "index_time_drafts_on_work_item_id"
  end

  create_table "work_items", force: :cascade do |t|
    t.string "jira_key", null: false
    t.string "summary"
    t.string "source", null: false
    t.bigint "project_id"
    t.bigint "batch_id"
    t.integer "agent_points"
    t.string "status", default: "queued", null: false
    t.datetime "enqueued_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_work_items_on_batch_id"
    t.index ["jira_key"], name: "index_work_items_on_jira_key", unique: true
    t.index ["project_id"], name: "index_work_items_on_project_id"
  end

  add_foreign_key "agent_runs", "work_items"
  add_foreign_key "attention_spans", "batches"
  add_foreign_key "attention_spans", "people"
  add_foreign_key "attention_spans", "work_items"
  add_foreign_key "batches", "people", column: "started_by_id"
  add_foreign_key "pipeline_events", "people"
  add_foreign_key "pipeline_events", "work_items"
  add_foreign_key "time_drafts", "people"
  add_foreign_key "time_drafts", "work_items"
  add_foreign_key "work_items", "batches"
  add_foreign_key "work_items", "projects"
end
