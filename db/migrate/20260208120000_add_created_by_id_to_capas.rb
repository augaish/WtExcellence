# frozen_string_literal: true

class AddCreatedByIdToCapas < ActiveRecord::Migration[8.0]
  def change
    add_column :capas, :created_by_id, :uuid
    add_index :capas, :created_by_id
    add_foreign_key :capas, :users, column: :created_by_id
  end
end
