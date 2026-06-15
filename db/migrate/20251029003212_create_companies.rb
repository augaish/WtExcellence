class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies, id: :uuid do |t|
      t.string :name, limit: 200
      t.integer :license_seats
      t.boolean :is_active
      t.string :default_locale, limit: 10

      t.timestamps
    end
  end
end
