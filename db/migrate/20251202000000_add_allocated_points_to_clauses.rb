class AddAllocatedPointsToClauses < ActiveRecord::Migration[8.0]
  def change
    add_column :clauses, :allocated_points, :decimal, precision: 10, scale: 2
    add_column :clauses, :base_points, :decimal, precision: 10, scale: 2
    
    add_index :clauses, :allocated_points
  end
end

