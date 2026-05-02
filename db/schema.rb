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

ActiveRecord::Schema[7.2].define(version: 2026_05_01_201454) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "po_generation_jobs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "job_type", null: false
    t.string "status", default: "pending"
    t.string "region"
    t.json "project_ids"
    t.integer "total_projects", default: 0
    t.integer "successful_pos", default: 0
    t.integer "failed_pos", default: 0
    t.json "po_results"
    t.datetime "locked_at"
    t.string "locked_by"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "skip_email", default: false
    t.index ["locked_at"], name: "index_po_generation_jobs_on_locked_at"
    t.index ["status", "region"], name: "index_po_generation_jobs_on_status_and_region"
    t.index ["user_id"], name: "index_po_generation_jobs_on_user_id"
  end

  create_table "po_generation_logs", force: :cascade do |t|
    t.bigint "po_generation_job_id", null: false
    t.string "level", null: false
    t.text "message", null: false
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["po_generation_job_id", "created_at"], name: "idx_on_po_generation_job_id_created_at_6e7489d212"
    t.index ["po_generation_job_id"], name: "index_po_generation_logs_on_po_generation_job_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "full_name"
    t.string "uid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "po_generation_jobs", "users"
  add_foreign_key "po_generation_logs", "po_generation_jobs"
end
