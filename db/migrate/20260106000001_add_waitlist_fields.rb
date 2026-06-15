class AddWaitlistFields < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :desired_role, :string
    add_column :companies, :company_size, :string
  end
end
