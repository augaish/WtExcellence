class CreateCompanyUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :company_users, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :role

      t.timestamps
    end

    add_index :company_users, [ :company_id, :user_id ], unique: true
  end
end
