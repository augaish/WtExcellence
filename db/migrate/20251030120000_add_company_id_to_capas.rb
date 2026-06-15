class AddCompanyIdToCapas < ActiveRecord::Migration[7.1]
  def change
    add_reference :capas, :company, type: :uuid, foreign_key: true, index: true, null: true
  end
end
