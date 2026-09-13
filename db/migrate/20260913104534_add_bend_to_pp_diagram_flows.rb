# An arrow can be bent through a point the user drags, kept as an offset from
# its straight midpoint so it survives the boxes being reordered.
class AddBendToPpDiagramFlows < ActiveRecord::Migration[8.0]
  def change
    add_column :pp_diagram_flows, :bend_dx, :integer
    add_column :pp_diagram_flows, :bend_dy, :integer
  end
end
