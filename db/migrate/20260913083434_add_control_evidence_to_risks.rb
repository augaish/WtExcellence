# The control owner reports on the control from a scoped task page: what was
# done and when it was submitted for the risk owner to assess.
class AddControlEvidenceToRisks < ActiveRecord::Migration[8.0]
  def change
    add_column :risks, :control_evidence_note, :text
    add_column :risks, :control_evidence_submitted_at, :datetime
  end
end
