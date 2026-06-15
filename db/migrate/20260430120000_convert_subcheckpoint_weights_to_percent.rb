class ConvertSubcheckpointWeightsToPercent < ActiveRecord::Migration[8.0]
  def up
    existing = ToolSubcheckpoint.where.not(weight: nil).pluck(:id, :weight)
    change_column :tool_subcheckpoints, :weight, :decimal, precision: 5, scale: 2
    existing.each do |id, w|
      ToolSubcheckpoint.where(id: id).update_all(weight: (w * 100).round(2))
    end
  end

  def down
    existing = ToolSubcheckpoint.where.not(weight: nil).pluck(:id, :weight)
    change_column :tool_subcheckpoints, :weight, :decimal, precision: 5, scale: 4
    existing.each do |id, w|
      ToolSubcheckpoint.where(id: id).update_all(weight: (w / 100.0).round(4))
    end
  end
end
