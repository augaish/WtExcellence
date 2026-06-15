# Move evidence_attachments from user link (ToolClauseSubcheckpointAssignmentsUser) to
# assignment container (ToolClauseSubcheckpointAssignment). Evidence is shared per assignment.
class MoveEvidenceAttachmentsToAssignmentContainer < ActiveRecord::Migration[8.0]
  def up
    EvidenceAttachment.where(attachable_type: "ToolClauseSubcheckpointAssignmentsUser").find_each do |ea|
      link = ToolClauseSubcheckpointAssignmentsUser.find_by(id: ea.attachable_id)
      next unless link

      container_id = link.tool_clause_subcheckpoint_assignment_id
      existing = EvidenceAttachment.find_by(
        attachable_type: "ToolClauseSubcheckpointAssignment",
        attachable_id: container_id,
        upload_id: ea.upload_id
      )
      if existing
        ea.destroy
      else
        ea.update_columns(attachable_type: "ToolClauseSubcheckpointAssignment", attachable_id: container_id)
      end
    end
  end

  def down
    # Re-attach to first user link per container (best-effort rollback)
    EvidenceAttachment.where(attachable_type: "ToolClauseSubcheckpointAssignment").find_each do |ea|
      link = ToolClauseSubcheckpointAssignmentsUser.find_by(tool_clause_subcheckpoint_assignment_id: ea.attachable_id)
      next unless link

      existing = EvidenceAttachment.find_by(
        attachable_type: "ToolClauseSubcheckpointAssignmentsUser",
        attachable_id: link.id,
        upload_id: ea.upload_id
      )
      if existing
        ea.destroy
      else
        ea.update_columns(attachable_type: "ToolClauseSubcheckpointAssignmentsUser", attachable_id: link.id)
      end
    end
  end
end
