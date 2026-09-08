class Dashboard::PpAuthorityAssignmentsController < Dashboard::PpProcessDetailController
  before_action :set_authority

  def create
    assignment = @authority.assignments.new(assignment_params)

    if assignment.save
      back_to_process(notice: t("process_authorities.flash.assignment_created"))
    else
      back_to_process(alert: assignment.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @authority.assignments.find_by(id: params[:id])&.destroy

    back_to_process(notice: t("process_authorities.flash.assignment_deleted"))
  end

  private

  def set_authority
    @authority = @process.authorities.find_by(id: params[:authority_id])
    back_to_process(alert: t("process_authorities.flash.not_found")) if @authority.nil?
  end

  def assignment_params
    params.require(:pp_authority_assignment).permit(:level, :holder_title, :org_unit_id, :condition)
  end
end
