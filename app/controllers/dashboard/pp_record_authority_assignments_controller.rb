# One cell of an operational authority: a holder at one level.
class Dashboard::PpRecordAuthorityAssignmentsController < Dashboard::DocumenterContentController
  before_action :set_authority

  def create
    assignment = @authority.assignments.new(assignment_params)
    if assignment.save
      back(notice: t("process_authorities.flash.assignment_created"))
    else
      back(alert: assignment.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @authority.assignments.find_by(id: params[:id])&.destroy
    back(notice: t("process_authorities.flash.assignment_deleted"))
  end

  private

  def set_authority
    @authority = @record.operational_authorities.find_by(id: params[:operational_authority_id])
    back(alert: t("process_authorities.flash.not_found")) if @authority.nil?
  end

  def assignment_params
    params.require(:pp_authority_assignment).permit(:level, :holder_title, :org_unit_id, :condition)
  end
end
