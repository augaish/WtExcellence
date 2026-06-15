class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :users, id: :uuid do |t|
      t.string :email, limit: 320
      t.string :name, limit: 200
      t.boolean :is_active
      t.string :locale_code, limit: 10

      t.timestamps
    end

    add_index :users, :email
  end
end
