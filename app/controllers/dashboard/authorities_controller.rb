# The executive authority matrix: the authorities a company's Executive DoA
# grants, the thresholds they are split by, and who holds each level.
class Dashboard::AuthoritiesController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, except: [ :index ]
  before_action :set_matrix

  helper_method :can_manage_authorities?

  def index
    return if @matrix.nil?

    @report = AuthorityMatrixReport.new(@matrix)
    @authorities = @report.authorities
    @categories = company.authority_categories.to_a
    @org_units = company.org_units.active.ordered.to_a
  end

  def create_category
    category = company.authority_categories.new(category_params)
    category.sort_order = company.authority_categories.maximum(:sort_order).to_i + 1

    save_and_return(category, "category_created")
  end

  def create_authority
    authority = company.authorities.new(authority_params)
    authority.matrix = @matrix
    authority.number = (@matrix.authorities.maximum(:number).to_i + 1)
    authority.sort_order = authority.number

    save_and_return(authority, "authority_created")
  end

  def create_band
    authority = @matrix.authorities.find_by(id: params[:authority_id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if authority.nil?

    band = authority.bands.new(band_params)
    band.sort_order = authority.bands.maximum(:sort_order).to_i + 1

    save_and_return(band, "band_created")
  end

  def create_assignment
    band = AuthorityBand.joins(:authority)
      .where(authorities: { matrix_id: @matrix.id }).find_by(id: params[:band_id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if band.nil?

    save_and_return(band.assignments.new(assignment_params), "assignment_created")
  end

  def destroy_authority
    @matrix.authorities.find_by(id: params[:id])&.destroy
    back_to_matrix(notice: t("doa.flash.deleted"))
  end

  def destroy_assignment
    AuthorityAssignment.joins(authority_band: :authority)
      .where(authorities: { matrix_id: @matrix.id }).find_by(id: params[:id])&.destroy

    back_to_matrix(notice: t("doa.flash.deleted"))
  end

  private

  def company
    @company ||= current_company
  end

  # The matrix being viewed: the one asked for, or the company's most recent.
  def set_matrix
    matrices = company.pp_records.of_type("executive_doa").order(version_number: :desc, created_at: :desc)
    @matrices = matrices.to_a
    @matrix = params[:matrix_id].present? ? matrices.find_by(id: params[:matrix_id]) : matrices.first
  end

  def save_and_return(record, flash_key)
    if record.save
      back_to_matrix(notice: t("doa.flash.#{flash_key}"))
    else
      back_to_matrix(alert: record.errors.full_messages.to_sentence)
    end
  end

  def back_to_matrix(notice: nil, alert: nil)
    redirect_to dashboard_authorities_path(matrix_id: @matrix&.id),
      notice: notice, alert: alert, status: :see_other
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("process_architecture.flash.no_company"), status: :see_other
  end

  def can_manage_authorities?
    return true if current_user&.platform_admin?

    membership = current_user&.company_user
    membership.present? && (membership.has_admin_privileges? || membership.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_authorities?

    redirect_to dashboard_authorities_path, alert: t("doa.flash.no_permission"), status: :see_other
  end

  def category_params
    params.require(:authority_category).permit(:code, :name_en, :name_ar)
  end

  def authority_params
    params.require(:authority).permit(:authority_category_id, :name_en, :name_ar, :notes,
      :basis_record_id, :basis_clause_id, :conflict_sensitive)
  end

  def band_params
    params.require(:authority_band).permit(:label_en, :label_ar, :min_amount, :max_amount)
  end

  def assignment_params
    params.require(:authority_assignment).permit(:level, :org_unit_id, :dynamic_role, :holder_title, :condition)
  end
end
