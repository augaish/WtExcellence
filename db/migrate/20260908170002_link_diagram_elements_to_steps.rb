class LinkDiagramElementsToSteps < ActiveRecord::Migration[8.0]
  def change
    # A task drawn from a procedure step remembers which step it came from, so
    # a change on either side can reach the other instead of the two drifting
    # into describing different procedures.
    add_reference :pp_diagram_elements, :pp_process_step, type: :uuid, null: true,
      foreign_key: true, index: true
  end
end
