class AddWeightAndIsCapToToolSubcheckpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_subcheckpoints, :weight, :decimal, precision: 5, scale: 4, null: true
    add_column :tool_subcheckpoints, :is_cap, :boolean, default: false, null: false
  end
end
