class CreateToolTranslations < ActiveRecord::Migration[8.0]
  def change
    tools_fk_type = foreign_key_column_type_for(:tools)
    checkpoints_fk_type = foreign_key_column_type_for(:tool_checkpoints)
    subcheckpoints_fk_type = foreign_key_column_type_for(:tool_subcheckpoints)

    create_table :tool_translations, id: :uuid do |t|
      t.references :tool, null: false, foreign_key: true, type: tools_fk_type
      t.string :language_code, null: false, limit: 10
      t.string :name, null: false
      t.text :description
      t.datetime :last_modified_at
      t.datetime :source_updated_at
      t.boolean :needs_review, default: false
      t.boolean :ai_generated, default: false
      t.timestamps
    end
    add_index :tool_translations, [ :tool_id, :language_code ], unique: true
    add_index :tool_translations, :needs_review
    add_index :tool_translations, :ai_generated
    add_foreign_key :tool_translations, :languages, column: :language_code, primary_key: :code

    create_table :tool_checkpoint_translations, id: :uuid do |t|
      t.references :tool_checkpoint, null: false, foreign_key: true, type: checkpoints_fk_type
      t.string :language_code, null: false, limit: 10
      t.string :name, null: false
      t.datetime :last_modified_at
      t.datetime :source_updated_at
      t.boolean :needs_review, default: false
      t.boolean :ai_generated, default: false
      t.timestamps
    end
    add_index :tool_checkpoint_translations, [ :tool_checkpoint_id, :language_code ], unique: true, name: "idx_tool_checkpoint_translations_unique_locale"
    add_index :tool_checkpoint_translations, :needs_review
    add_index :tool_checkpoint_translations, :ai_generated
    add_foreign_key :tool_checkpoint_translations, :languages, column: :language_code, primary_key: :code

    create_table :tool_subcheckpoint_translations, id: :uuid do |t|
      t.references :tool_subcheckpoint, null: false, foreign_key: true, type: subcheckpoints_fk_type
      t.string :language_code, null: false, limit: 10
      t.string :name, null: false
      t.text :description
      t.jsonb :multiple_choice_options, default: []
      t.datetime :last_modified_at
      t.datetime :source_updated_at
      t.boolean :needs_review, default: false
      t.boolean :ai_generated, default: false
      t.timestamps
    end
    add_index :tool_subcheckpoint_translations, [ :tool_subcheckpoint_id, :language_code ], unique: true, name: "idx_tool_subcheckpoint_translations_unique_locale"
    add_index :tool_subcheckpoint_translations, :needs_review
    add_index :tool_subcheckpoint_translations, :ai_generated
    add_foreign_key :tool_subcheckpoint_translations, :languages, column: :language_code, primary_key: :code
  end

  private

  def foreign_key_column_type_for(table_name)
    primary_key_name = connection.primary_key(table_name)
    primary_key_column = connection.columns(table_name).find { |column| column.name == primary_key_name }
    primary_key_column.sql_type_metadata.type
  end
end
