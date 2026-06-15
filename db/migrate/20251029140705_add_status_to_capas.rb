class AddStatusToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :status, :string
  end
end
