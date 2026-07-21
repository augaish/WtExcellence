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

ActiveRecord::Schema[8.0].define(version: 2026_07_19_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.string "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_action_credits", force: :cascade do |t|
    t.string "action_type", null: false
    t.integer "credit_cost", default: 0, null: false
    t.string "display_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_type"], name: "index_ai_action_credits_on_action_type", unique: true
  end

  create_table "ai_instructions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "title", null: false
    t.text "content_en"
    t.text "content_ar"
    t.boolean "active", default: true, null: false
    t.uuid "created_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_ai_instructions_on_company_id"
    t.index ["created_by_id"], name: "index_ai_instructions_on_created_by_id"
    t.index ["deleted_at"], name: "index_ai_instructions_on_deleted_at"
  end

  create_table "assessment_scores", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "assessment_id", null: false
    t.uuid "tool_subcheckpoint_id", null: false
    t.decimal "score", precision: 10, scale: 2
    t.decimal "percentage_score", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_id", "tool_subcheckpoint_id"], name: "idx_assessment_scores_unique", unique: true
    t.index ["assessment_id"], name: "index_assessment_scores_on_assessment_id"
    t.index ["tool_subcheckpoint_id"], name: "index_assessment_scores_on_tool_subcheckpoint_id"
  end

  create_table "assessment_users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "assessment_id", null: false
    t.uuid "user_id", null: false
    t.string "role", null: false
    t.uuid "assigner_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "checklist_item_id"
    t.index ["assessment_id", "user_id", "checklist_item_id"], name: "idx_assessment_users_unique", unique: true
    t.index ["assessment_id"], name: "index_assessment_users_on_assessment_id"
    t.index ["checklist_item_id"], name: "index_assessment_users_on_checklist_item_id"
    t.index ["user_id"], name: "index_assessment_users_on_user_id"
  end

  create_table "assessments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_clause_id", null: false
    t.uuid "company_id", null: false
    t.string "status", default: "not_started", null: false
    t.date "due_date"
    t.uuid "last_edited_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_assessments_on_company_id"
    t.index ["status"], name: "index_assessments_on_status"
    t.index ["tool_clause_id", "company_id"], name: "idx_assessments_unique_tool_clause_company", unique: true
    t.index ["tool_clause_id"], name: "index_assessments_on_tool_clause_id"
  end

  create_table "assignment_evaluations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "evaluator_id", null: false
    t.decimal "score"
    t.string "evaluation_status", null: false
    t.text "feedback"
    t.text "comments"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "assessment_id"
    t.index ["assessment_id"], name: "index_assignment_evaluations_on_assessment_id"
    t.index ["evaluator_id"], name: "index_assignment_evaluations_on_evaluator_id"
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_user_id"
    t.uuid "company_id", null: false
    t.string "action", limit: 200, null: false
    t.string "entity_type", limit: 100
    t.uuid "entity_id"
    t.jsonb "payload_json"
    t.timestamptz "created_at", default: -> { "now()" }, null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_user_id"], name: "index_audit_logs_on_actor_user_id"
    t.index ["company_id"], name: "index_audit_logs_on_company_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["entity_type", "entity_id"], name: "index_audit_logs_on_entity_type_and_entity_id"
  end

  create_table "capa_action_assignments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capa_action_id", null: false
    t.uuid "company_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capa_action_id", "company_user_id"], name: "idx_on_capa_action_id_company_user_id_6c29223d00", unique: true
    t.index ["capa_action_id"], name: "index_capa_action_assignments_on_capa_action_id"
    t.index ["company_user_id"], name: "index_capa_action_assignments_on_company_user_id"
  end

  create_table "capa_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capa_id", null: false
    t.string "title", null: false
    t.string "action_type", null: false
    t.string "status", null: false
    t.date "due_date"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.index ["capa_id"], name: "index_capa_actions_on_capa_id"
    t.index ["created_by_id"], name: "index_capa_actions_on_created_by_id"
  end

  create_table "capa_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capa_id", null: false
    t.string "activity_type", null: false
    t.text "description", null: false
    t.jsonb "metadata", default: {}
    t.uuid "performed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capa_id", "created_at"], name: "index_capa_activities_on_capa_id_and_created_at"
    t.index ["capa_id"], name: "index_capa_activities_on_capa_id"
    t.index ["performed_by_id"], name: "index_capa_activities_on_performed_by_id"
  end

  create_table "capa_assignments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capa_id", null: false
    t.uuid "company_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capa_id", "company_user_id"], name: "index_capa_assignments_on_capa_id_and_company_user_id", unique: true
    t.index ["capa_id"], name: "index_capa_assignments_on_capa_id"
    t.index ["company_user_id"], name: "index_capa_assignments_on_company_user_id"
  end

  create_table "capa_clauses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capa_id", null: false
    t.uuid "clause_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capa_id", "clause_id"], name: "index_capa_clauses_on_capa_id_and_clause_id", unique: true
    t.index ["capa_id"], name: "index_capa_clauses_on_capa_id"
    t.index ["clause_id"], name: "index_capa_clauses_on_clause_id"
  end

  create_table "capas", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "source"
    t.string "priority"
    t.uuid "standard_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "due_date"
    t.string "status"
    t.uuid "company_id"
    t.string "analysis_method", default: "manual"
    t.boolean "archived", default: false, null: false
    t.integer "friendly_id"
    t.uuid "created_by_id"
    t.string "origin_type"
    t.uuid "origin_id"
    t.index ["archived"], name: "index_capas_on_archived"
    t.index ["company_id", "friendly_id"], name: "index_capas_on_company_id_and_friendly_id", unique: true
    t.index ["company_id"], name: "index_capas_on_company_id"
    t.index ["created_by_id"], name: "index_capas_on_created_by_id"
    t.index ["origin_type", "origin_id"], name: "index_capas_on_origin_type_and_origin_id"
    t.index ["standard_id"], name: "index_capas_on_standard_id"
  end

  create_table "checklist_item_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "checklist_item_id", null: false
    t.string "language_code", limit: 10, null: false
    t.text "text", null: false
    t.text "guidance"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_modified_at"
    t.datetime "source_updated_at"
    t.boolean "needs_review", default: false
    t.boolean "ai_generated", default: false
    t.index ["ai_generated"], name: "index_checklist_item_translations_on_ai_generated"
    t.index ["checklist_item_id", "language_code"], name: "idx_on_checklist_item_id_language_code_f47d26aa9d", unique: true
    t.index ["checklist_item_id"], name: "index_checklist_item_translations_on_checklist_item_id"
    t.index ["needs_review"], name: "index_checklist_item_translations_on_needs_review"
  end

  create_table "checklist_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clause_id", null: false
    t.string "item_type", limit: 20, default: "requirement", null: false
    t.string "code", limit: 100
    t.integer "sort_order", default: 0, null: false
    t.string "stable_key", limit: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clause_id", "code"], name: "index_checklist_items_on_clause_id_and_code"
    t.index ["clause_id", "sort_order"], name: "index_checklist_items_on_clause_id_and_sort_order"
    t.index ["clause_id"], name: "index_checklist_items_on_clause_id"
    t.index ["stable_key"], name: "index_checklist_items_on_stable_key"
  end

  create_table "checkpoint_summaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_clause_id", null: false
    t.uuid "checklist_item_id", null: false
    t.uuid "tool_checkpoint_id", null: false
    t.uuid "company_id", null: false
    t.text "summary"
    t.uuid "last_edited_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_item_id"], name: "index_checkpoint_summaries_on_checklist_item_id"
    t.index ["company_id"], name: "index_checkpoint_summaries_on_company_id"
    t.index ["tool_checkpoint_id"], name: "index_checkpoint_summaries_on_tool_checkpoint_id"
    t.index ["tool_clause_id", "checklist_item_id", "tool_checkpoint_id", "company_id"], name: "idx_checkpoint_summaries_unique_key", unique: true
    t.index ["tool_clause_id"], name: "index_checkpoint_summaries_on_tool_clause_id"
  end

  create_table "clause_score_caches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clause_id", null: false
    t.uuid "company_id", null: false
    t.decimal "cached_score", precision: 10, scale: 2
    t.decimal "cached_percentage", precision: 5, scale: 2
    t.integer "cached_evaluated_count"
    t.datetime "cached_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "business_rule_violation"
    t.index ["cached_at"], name: "index_clause_score_caches_on_cached_at"
    t.index ["clause_id", "company_id"], name: "index_clause_score_caches_on_clause_and_company", unique: true
    t.index ["company_id"], name: "index_clause_score_caches_on_company_id"
  end

  create_table "clause_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "clause_id", null: false
    t.string "language_code", limit: 10, null: false
    t.string "title", limit: 500, null: false
    t.text "summary"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_modified_at"
    t.datetime "source_updated_at"
    t.boolean "needs_review", default: false
    t.boolean "ai_generated", default: false
    t.index ["ai_generated"], name: "index_clause_translations_on_ai_generated"
    t.index ["clause_id", "language_code"], name: "index_clause_translations_on_clause_id_and_language_code", unique: true
    t.index ["clause_id"], name: "index_clause_translations_on_clause_id"
    t.index ["needs_review"], name: "index_clause_translations_on_needs_review"
  end

  create_table "clauses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "standard_version_id", null: false
    t.uuid "parent_id"
    t.string "code", limit: 100, null: false
    t.integer "sort_order", default: 0, null: false
    t.string "stable_key", limit: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "allocated_points", precision: 10, scale: 2
    t.decimal "base_points", precision: 10, scale: 2
    t.index ["allocated_points"], name: "index_clauses_on_allocated_points"
    t.index ["parent_id"], name: "index_clauses_on_parent_id"
    t.index ["stable_key"], name: "index_clauses_on_stable_key"
    t.index ["standard_version_id", "code"], name: "index_clauses_on_standard_version_id_and_code", unique: true
    t.index ["standard_version_id", "parent_id", "sort_order"], name: "idx_on_standard_version_id_parent_id_sort_order_c851e9efe7"
    t.index ["standard_version_id"], name: "index_clauses_on_standard_version_id"
  end

  create_table "comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "commentable_type", null: false
    t.uuid "commentable_id", null: false
    t.uuid "user_id", null: false
    t.uuid "parent_id"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable_type_and_commentable_id"
    t.index ["parent_id"], name: "index_comments_on_parent_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "companies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 200
    t.integer "license_seats"
    t.boolean "is_active"
    t.string "default_locale", limit: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "credits", default: 1000, null: false
    t.string "status", default: "active"
    t.string "company_size"
    t.boolean "trust_center_enabled", default: false, null: false
    t.index ["status"], name: "index_companies_on_status"
  end

  create_table "company_checklist_item_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_clause_instance_id", null: false
    t.uuid "checklist_item_id", null: false
    t.string "status", default: "not_started", null: false
    t.uuid "assigned_to"
    t.date "due_date"
    t.uuid "last_updated_by"
    t.datetime "last_updated_at", default: -> { "now()" }
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_to"], name: "index_company_checklist_item_instances_on_assigned_to"
    t.index ["checklist_item_id"], name: "index_company_checklist_item_instances_on_checklist_item_id"
    t.index ["company_clause_instance_id", "checklist_item_id"], name: "idx_on_company_clause_instance_id_checklist_item_id_0e9f26267e", unique: true
    t.index ["company_clause_instance_id"], name: "idx_on_company_clause_instance_id_eacd3a2f15"
    t.index ["last_updated_by"], name: "index_company_checklist_item_instances_on_last_updated_by"
    t.index ["status"], name: "index_company_checklist_item_instances_on_status"
  end

  create_table "company_clause_instances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_standard_id", null: false
    t.uuid "clause_id", null: false
    t.string "clause_code", limit: 100
    t.uuid "version_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clause_code"], name: "index_company_clause_instances_on_clause_code"
    t.index ["clause_id"], name: "index_company_clause_instances_on_clause_id"
    t.index ["company_standard_id", "clause_id"], name: "idx_on_company_standard_id_clause_id_1870072648", unique: true
    t.index ["company_standard_id"], name: "index_company_clause_instances_on_company_standard_id"
    t.index ["version_id"], name: "index_company_clause_instances_on_version_id"
  end

  create_table "company_modules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "module_key", limit: 50, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "module_key"], name: "index_company_modules_on_company_id_and_module_key", unique: true
    t.index ["company_id"], name: "index_company_modules_on_company_id"
  end

  create_table "company_standard_version_history", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_standard_id", null: false
    t.uuid "from_version_id"
    t.uuid "to_version_id", null: false
    t.uuid "changed_by"
    t.datetime "changed_at", default: -> { "now()" }
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["changed_at"], name: "index_company_standard_version_history_on_changed_at"
    t.index ["changed_by"], name: "index_company_standard_version_history_on_changed_by"
    t.index ["company_standard_id"], name: "index_company_standard_version_history_on_company_standard_id"
    t.index ["from_version_id"], name: "index_company_standard_version_history_on_from_version_id"
    t.index ["to_version_id"], name: "index_company_standard_version_history_on_to_version_id"
  end

  create_table "company_standards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "standard_id", null: false
    t.string "status", default: "active", null: false
    t.uuid "active_version_id", null: false
    t.uuid "assigned_by"
    t.datetime "assigned_at", default: -> { "now()" }
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "cached_compliance_percentage", precision: 5, scale: 2
    t.datetime "cached_compliance_at"
    t.decimal "cached_total_scored_points", precision: 10, scale: 2
    t.decimal "cached_total_allocated_points", precision: 10, scale: 2
    t.index ["active_version_id"], name: "index_company_standards_on_active_version_id"
    t.index ["assigned_by"], name: "index_company_standards_on_assigned_by"
    t.index ["cached_compliance_percentage"], name: "index_company_standards_on_cached_compliance_percentage"
    t.index ["company_id", "standard_id"], name: "index_company_standards_on_company_id_and_standard_id", unique: true
    t.index ["company_id"], name: "index_company_standards_on_company_id"
    t.index ["standard_id"], name: "index_company_standards_on_standard_id"
  end

  create_table "company_users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assigned_credits", default: 0, null: false
    t.index ["company_id", "user_id"], name: "index_company_users_on_company_id_and_user_id", unique: true
    t.index ["company_id"], name: "index_company_users_on_company_id"
    t.index ["user_id"], name: "index_company_users_on_user_id"
  end

  create_table "customer_commitments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "customer_name"
    t.date "due_date"
    t.string "status", default: "open", null: false
    t.uuid "owner_id"
    t.uuid "created_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_customer_commitments_on_company_id"
    t.index ["created_by_id"], name: "index_customer_commitments_on_created_by_id"
    t.index ["deleted_at"], name: "index_customer_commitments_on_deleted_at"
    t.index ["owner_id"], name: "index_customer_commitments_on_owner_id"
    t.index ["status"], name: "index_customer_commitments_on_status"
  end

  create_table "dashboard_layouts", force: :cascade do |t|
    t.uuid "company_id"
    t.string "scope", default: "company", null: false
    t.integer "slot", default: 1, null: false
    t.string "name"
    t.jsonb "config", default: {}, null: false
    t.boolean "is_active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "scope", "slot"], name: "index_dashboard_layouts_on_company_scope_slot", unique: true
    t.index ["company_id"], name: "index_dashboard_layouts_on_company_id"
  end

  create_table "evidence_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "upload_id", null: false
    t.uuid "attachable_id", null: false
    t.string "attachable_type", limit: 50, null: false
    t.string "purpose", limit: 50
    t.text "notes"
    t.uuid "attached_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attachable_type", "attachable_id"], name: "index_evidence_attachments_on_attachable"
    t.index ["attached_by"], name: "index_evidence_attachments_on_attached_by"
    t.index ["upload_id", "attachable_type", "attachable_id"], name: "index_evidence_attachments_on_upload_and_attachable", unique: true
    t.index ["upload_id"], name: "index_evidence_attachments_on_upload_id"
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.text "description"
    t.uuid "created_by"
    t.integer "files_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id"
    t.string "color", default: "#5C3984", null: false
    t.uuid "parent_id"
    t.index ["company_id"], name: "index_folders_on_company_id"
    t.index ["created_by"], name: "index_folders_on_created_by"
    t.index ["parent_id"], name: "index_folders_on_parent_id"
  end

  create_table "ingestion_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "standard_id"
    t.uuid "input_pdf_id", null: false
    t.string "status", default: "queued", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "message"
    t.uuid "created_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "progress_stage"
    t.datetime "heartbeat_at"
    t.string "progress_detail"
  end

  create_table "languages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", limit: 10, null: false
    t.string "name", limit: 100, null: false
    t.string "direction", limit: 3, default: "ltr", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_languages_on_code", unique: true
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "recipient_id", null: false
    t.string "kind", limit: 100, null: false
    t.string "title", limit: 500
    t.text "body"
    t.string "link_path", limit: 500
    t.timestamptz "read_at"
    t.string "source_type", limit: 100
    t.uuid "source_id"
    t.jsonb "payload", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["recipient_id", "read_at"], name: "index_notifications_on_recipient_id_and_read_at"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
    t.index ["source_type", "source_id"], name: "index_notifications_on_source_type_and_source_id"
  end

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.string "searchable_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "searchable_id"
    t.tsvector "tsvector_content"
    t.index ["content"], name: "index_pg_search_documents_on_content_gin", opclass: :gin_trgm_ops, using: :gin
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
    t.index ["tsvector_content"], name: "index_pg_search_documents_on_tsvector_content_gin", using: :gin
  end

  create_table "questionnaires", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capa_id", null: false
    t.text "question_1"
    t.text "question_2"
    t.text "question_3"
    t.text "question_4"
    t.text "question_5"
    t.text "answer_1"
    t.text "answer_2"
    t.text "answer_3"
    t.text "answer_4"
    t.text "answer_5"
    t.text "root_cause"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capa_id"], name: "index_questionnaires_on_capa_id", unique: true
  end

  create_table "risk_workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "framework"
    t.text "description"
    t.string "department_scope"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_risk_workspaces_on_company_id"
    t.index ["deleted_at"], name: "index_risk_workspaces_on_deleted_at"
  end

  create_table "risks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "owner_id"
    t.uuid "created_by_id"
    t.string "title", null: false
    t.text "description"
    t.string "category"
    t.uuid "riskable_id"
    t.string "riskable_type", limit: 50
    t.integer "likelihood", default: 1, null: false
    t.integer "impact", default: 1, null: false
    t.integer "inherent_score", default: 1, null: false
    t.integer "residual_likelihood"
    t.integer "residual_impact"
    t.integer "residual_score"
    t.string "status", default: "identified", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "risk_workspace_id"
    t.index ["company_id"], name: "index_risks_on_company_id"
    t.index ["created_by_id"], name: "index_risks_on_created_by_id"
    t.index ["deleted_at"], name: "index_risks_on_deleted_at"
    t.index ["owner_id"], name: "index_risks_on_owner_id"
    t.index ["risk_workspace_id"], name: "index_risks_on_risk_workspace_id"
    t.index ["riskable_type", "riskable_id"], name: "index_risks_on_riskable"
    t.index ["status"], name: "index_risks_on_status"
  end

  create_table "standard_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "standard_id", null: false
    t.string "language_code", limit: 10, null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["standard_id", "language_code"], name: "index_standard_translations_on_standard_id_and_language_code", unique: true
    t.index ["standard_id"], name: "index_standard_translations_on_standard_id"
  end

  create_table "standard_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "standard_id", null: false
    t.string "version_label", limit: 100, null: false
    t.uuid "source_pdf_id"
    t.string "status", limit: 30, default: "published", null: false
    t.datetime "published_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_pdf_id"], name: "index_standard_versions_on_source_pdf_id"
    t.index ["standard_id", "version_label"], name: "index_standard_versions_on_standard_id_and_version_label", unique: true
    t.index ["standard_id"], name: "index_standard_versions_on_standard_id"
  end

  create_table "standards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", limit: 100, null: false
    t.boolean "is_primary", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pipeline_type", limit: 50
    t.index ["code"], name: "index_standards_on_code", unique: true
  end

  create_table "tool_checkpoint_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_checkpoint_id", null: false
    t.string "language_code", limit: 10, null: false
    t.string "name", null: false
    t.datetime "last_modified_at"
    t.datetime "source_updated_at"
    t.boolean "needs_review", default: false
    t.boolean "ai_generated", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_generated"], name: "index_tool_checkpoint_translations_on_ai_generated"
    t.index ["needs_review"], name: "index_tool_checkpoint_translations_on_needs_review"
    t.index ["tool_checkpoint_id", "language_code"], name: "idx_tool_checkpoint_translations_unique_locale", unique: true
    t.index ["tool_checkpoint_id"], name: "index_tool_checkpoint_translations_on_tool_checkpoint_id"
  end

  create_table "tool_checkpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_id", null: false
    t.string "name"
    t.text "description"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_id"], name: "index_tool_checkpoints_on_tool_id"
  end

  create_table "tool_clauses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_id", null: false
    t.uuid "clause_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clause_id"], name: "index_tool_clauses_on_clause_id", unique: true
    t.index ["tool_id", "clause_id"], name: "index_tool_clauses_on_tool_id_and_clause_id", unique: true
    t.index ["tool_id"], name: "index_tool_clauses_on_tool_id"
  end

  create_table "tool_subcheckpoint_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_subcheckpoint_id", null: false
    t.string "language_code", limit: 10, null: false
    t.string "name", null: false
    t.text "description"
    t.jsonb "multiple_choice_options", default: []
    t.datetime "last_modified_at"
    t.datetime "source_updated_at"
    t.boolean "needs_review", default: false
    t.boolean "ai_generated", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_generated"], name: "index_tool_subcheckpoint_translations_on_ai_generated"
    t.index ["needs_review"], name: "index_tool_subcheckpoint_translations_on_needs_review"
    t.index ["tool_subcheckpoint_id", "language_code"], name: "idx_tool_subcheckpoint_translations_unique_locale", unique: true
    t.index ["tool_subcheckpoint_id"], name: "index_tool_subcheckpoint_translations_on_tool_subcheckpoint_id"
  end

  create_table "tool_subcheckpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_checkpoints_id", null: false
    t.string "name"
    t.text "description"
    t.string "scoring_type"
    t.decimal "min_score"
    t.decimal "max_score"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "multiple_choice_options", default: []
    t.decimal "weight", precision: 5, scale: 2
    t.boolean "is_cap", default: false, null: false
    t.index ["tool_checkpoints_id"], name: "index_tool_subcheckpoints_on_tool_checkpoints_id"
  end

  create_table "tool_translations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tool_id", null: false
    t.string "language_code", limit: 10, null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "last_modified_at"
    t.datetime "source_updated_at"
    t.boolean "needs_review", default: false
    t.boolean "ai_generated", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_generated"], name: "index_tool_translations_on_ai_generated"
    t.index ["needs_review"], name: "index_tool_translations_on_needs_review"
    t.index ["tool_id", "language_code"], name: "index_tool_translations_on_tool_id_and_language_code", unique: true
    t.index ["tool_id"], name: "index_tool_translations_on_tool_id"
  end

  create_table "tools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "business_rules", default: {}
    t.index ["business_rules"], name: "index_tools_on_business_rules", using: :gin
    t.index ["name"], name: "index_tools_on_name", unique: true
  end

  create_table "uploads", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "filename", limit: 255, null: false
    t.string "mime_type"
    t.bigint "size_bytes"
    t.uuid "uploaded_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "folder_id"
    t.string "name", limit: 255
    t.text "notes"
    t.uuid "company_id"
    t.string "visibility", default: "public", null: false
    t.index ["company_id"], name: "index_uploads_on_company_id"
    t.index ["folder_id"], name: "index_uploads_on_folder_id"
    t.index ["visibility"], name: "index_uploads_on_visibility"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", limit: 320
    t.string "name", limit: 200
    t.boolean "is_active"
    t.string "locale_code", limit: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "role"
    t.string "invitation_token"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.datetime "invitation_expires_at"
    t.uuid "invited_by_id"
    t.jsonb "permissions", default: [], null: false
    t.string "status", default: "active"
    t.string "desired_role"
    t.boolean "receive_notifications_on_email", default: true, null: false
    t.datetime "deleted_at"
    t.datetime "user_manual_seen_at"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email"
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["permissions"], name: "index_users_on_permissions", using: :gin
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["status"], name: "index_users_on_status"
  end

  create_table "vendors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "category"
    t.string "risk_level", default: "unassessed", null: false
    t.string "contact_email"
    t.uuid "owner_id"
    t.uuid "created_by_id"
    t.text "notes"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_vendors_on_company_id"
    t.index ["created_by_id"], name: "index_vendors_on_created_by_id"
    t.index ["deleted_at"], name: "index_vendors_on_deleted_at"
    t.index ["owner_id"], name: "index_vendors_on_owner_id"
    t.index ["risk_level"], name: "index_vendors_on_risk_level"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_instructions", "companies"
  add_foreign_key "ai_instructions", "users", column: "created_by_id"
  add_foreign_key "assessment_scores", "assessments"
  add_foreign_key "assessment_scores", "tool_subcheckpoints"
  add_foreign_key "assessment_users", "assessments"
  add_foreign_key "assessment_users", "checklist_items"
  add_foreign_key "assessment_users", "users"
  add_foreign_key "assessment_users", "users", column: "assigner_user_id"
  add_foreign_key "assessments", "companies"
  add_foreign_key "assessments", "tool_clauses"
  add_foreign_key "assessments", "users", column: "last_edited_by_user_id"
  add_foreign_key "assignment_evaluations", "assessments"
  add_foreign_key "assignment_evaluations", "users", column: "evaluator_id"
  add_foreign_key "audit_logs", "companies"
  add_foreign_key "audit_logs", "users", column: "actor_user_id", on_delete: :nullify
  add_foreign_key "capa_action_assignments", "capa_actions"
  add_foreign_key "capa_action_assignments", "company_users"
  add_foreign_key "capa_actions", "capas"
  add_foreign_key "capa_actions", "users", column: "created_by_id"
  add_foreign_key "capa_activities", "capas"
  add_foreign_key "capa_activities", "users", column: "performed_by_id"
  add_foreign_key "capa_assignments", "capas"
  add_foreign_key "capa_assignments", "company_users"
  add_foreign_key "capa_clauses", "capas"
  add_foreign_key "capa_clauses", "clauses"
  add_foreign_key "capas", "companies"
  add_foreign_key "capas", "standards"
  add_foreign_key "capas", "users", column: "created_by_id"
  add_foreign_key "checklist_item_translations", "checklist_items"
  add_foreign_key "checklist_item_translations", "languages", column: "language_code", primary_key: "code"
  add_foreign_key "checklist_items", "clauses"
  add_foreign_key "checkpoint_summaries", "checklist_items"
  add_foreign_key "checkpoint_summaries", "companies"
  add_foreign_key "checkpoint_summaries", "tool_checkpoints"
  add_foreign_key "checkpoint_summaries", "tool_clauses"
  add_foreign_key "checkpoint_summaries", "users", column: "last_edited_by_user_id"
  add_foreign_key "clause_score_caches", "clauses"
  add_foreign_key "clause_score_caches", "companies"
  add_foreign_key "clause_translations", "clauses"
  add_foreign_key "clause_translations", "languages", column: "language_code", primary_key: "code"
  add_foreign_key "clauses", "clauses", column: "parent_id"
  add_foreign_key "clauses", "standard_versions"
  add_foreign_key "comments", "users"
  add_foreign_key "company_checklist_item_instances", "checklist_items"
  add_foreign_key "company_checklist_item_instances", "company_clause_instances"
  add_foreign_key "company_checklist_item_instances", "users", column: "assigned_to"
  add_foreign_key "company_checklist_item_instances", "users", column: "last_updated_by"
  add_foreign_key "company_clause_instances", "clauses"
  add_foreign_key "company_clause_instances", "company_standards"
  add_foreign_key "company_clause_instances", "standard_versions", column: "version_id"
  add_foreign_key "company_modules", "companies"
  add_foreign_key "company_standard_version_history", "company_standards"
  add_foreign_key "company_standard_version_history", "standard_versions", column: "from_version_id"
  add_foreign_key "company_standard_version_history", "standard_versions", column: "to_version_id"
  add_foreign_key "company_standard_version_history", "users", column: "changed_by"
  add_foreign_key "company_standards", "companies"
  add_foreign_key "company_standards", "standard_versions", column: "active_version_id"
  add_foreign_key "company_standards", "standards"
  add_foreign_key "company_standards", "users", column: "assigned_by"
  add_foreign_key "company_users", "companies"
  add_foreign_key "company_users", "users"
  add_foreign_key "customer_commitments", "companies"
  add_foreign_key "customer_commitments", "company_users", column: "owner_id"
  add_foreign_key "customer_commitments", "users", column: "created_by_id"
  add_foreign_key "dashboard_layouts", "companies"
  add_foreign_key "evidence_attachments", "uploads"
  add_foreign_key "folders", "companies"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "ingestion_jobs", "uploads", column: "input_pdf_id"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "questionnaires", "capas"
  add_foreign_key "risk_workspaces", "companies"
  add_foreign_key "risks", "companies"
  add_foreign_key "risks", "company_users", column: "owner_id"
  add_foreign_key "risks", "risk_workspaces"
  add_foreign_key "risks", "users", column: "created_by_id"
  add_foreign_key "standard_translations", "languages", column: "language_code", primary_key: "code"
  add_foreign_key "standard_translations", "standards"
  add_foreign_key "standard_versions", "standards"
  add_foreign_key "standard_versions", "uploads", column: "source_pdf_id"
  add_foreign_key "tool_checkpoint_translations", "languages", column: "language_code", primary_key: "code"
  add_foreign_key "tool_checkpoint_translations", "tool_checkpoints"
  add_foreign_key "tool_checkpoints", "tools"
  add_foreign_key "tool_clauses", "clauses"
  add_foreign_key "tool_clauses", "tools"
  add_foreign_key "tool_subcheckpoint_translations", "languages", column: "language_code", primary_key: "code"
  add_foreign_key "tool_subcheckpoint_translations", "tool_subcheckpoints"
  add_foreign_key "tool_subcheckpoints", "tool_checkpoints", column: "tool_checkpoints_id"
  add_foreign_key "tool_translations", "languages", column: "language_code", primary_key: "code"
  add_foreign_key "tool_translations", "tools"
  add_foreign_key "uploads", "companies"
  add_foreign_key "uploads", "folders"
  add_foreign_key "users", "users", column: "invited_by_id"
  add_foreign_key "vendors", "companies"
  add_foreign_key "vendors", "company_users", column: "owner_id"
  add_foreign_key "vendors", "users", column: "created_by_id"
end
