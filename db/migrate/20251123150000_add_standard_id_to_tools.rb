class AddStandardIdToTools < ActiveRecord::Migration[8.0]
  def change
    add_reference :tools, :standard, null: true, foreign_key: true, type: :uuid
  end
end
