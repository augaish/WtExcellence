class CreateVendors < ActiveRecord::Migration[8.0]
  def change
    create_table :vendors, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :category
      t.string :risk_level, null: false, default: "unassessed"
      t.string :contact_email
      t.references :owner, foreign_key: { to_table: :company_users }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :vendors, :risk_level
    add_index :vendors, :deleted_at
  end
end
