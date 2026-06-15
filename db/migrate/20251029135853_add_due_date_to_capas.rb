class AddDueDateToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :due_date, :date
  end
end
