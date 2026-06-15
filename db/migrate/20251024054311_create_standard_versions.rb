class CreateStandardVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :standard_versions, id: :uuid do |t|
      t.references :standard, null: false, foreign_key: true, type: :uuid
      t.string :version_label, null: false, limit: 100
      t.references :source_pdf, null: true, foreign_key: { to_table: :uploads }, type: :uuid
      t.string :status, null: false, default: 'published', limit: 30
      t.datetime :published_at
      t.text :notes

      t.timestamps
    end

    add_index :standard_versions, [ :standard_id, :version_label ], unique: true
  end
end
