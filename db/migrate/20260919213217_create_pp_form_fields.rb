# A form is fields and tables to fill in, not prose. Each row is one field of
# the form; a table field carries its column names.
class CreatePpFormFields < ActiveRecord::Migration[8.0]
  def change
    create_table :pp_form_fields, id: :uuid do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :label_en, limit: 250
      t.string :label_ar, limit: 250
      t.string :field_type, limit: 20, null: false, default: "text"
      t.boolean :required, null: false, default: false
      t.text :options
      t.text :columns
      t.string :hint, limit: 500
      t.timestamps
    end
  end
end
