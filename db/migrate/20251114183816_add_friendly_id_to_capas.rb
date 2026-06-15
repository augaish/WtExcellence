class AddFriendlyIdToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :friendly_id, :integer
    add_index :capas, [ :company_id, :friendly_id ], unique: true, name: 'index_capas_on_company_id_and_friendly_id'
  end
end
