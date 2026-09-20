# A procedure's KPIs as rows: name, target, unit and how it is measured,
# instead of a paragraph nobody can report against.
class CreatePpRecordKpis < ActiveRecord::Migration[8.0]
  def change
    create_table :pp_record_kpis, id: :uuid do |t|
      t.references :pp_record, type: :uuid, null: false, foreign_key: true
      t.string :name_en, limit: 250
      t.string :name_ar, limit: 250
      t.string :target, limit: 100
      t.string :unit, limit: 50
      t.string :measurement_method, limit: 500
      t.string :frequency, limit: 20
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
  end
end
