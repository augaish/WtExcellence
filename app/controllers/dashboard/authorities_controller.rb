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
    @company_users = company.users.order(:name).to_a
    @diff = AuthorityMatrixDiff.new(@matrix.previous_version, @matrix) if @matrix.previous_version
    @consultations = @matrix.consultations.includes(:authority, :org_unit, :ruled_by).to_a
    @suggested_categories = AuthorityCatalogue.categories
    @delegations = company.authority_delegations
      .includes(:authority, :from_org_unit, :to_org_unit, :parent_delegation).to_a
  end

  # Suggestions are applied only when asked for, and become ordinary editable
  # records — never seeded data the company did not choose.
  def apply_suggestions
    keys = Array(params[:category_keys]).map(&:to_s)
    return back_to_matrix(alert: t("doa.catalogue.none_selected")) if keys.empty?

    created = AuthorityCatalogue.apply(@matrix, category_keys: keys, locale: I18n.locale)
    back_to_matrix(notice: t("doa.catalogue.applied",
      categories: created[:categories], authorities: created[:authorities]))
  end

  def create_delegation
    delegation = company.authority_delegations.new(delegation_params)

    save_and_return(delegation, "delegation_created")
  end

  def revoke_delegation
    delegation = company.authority_delegations.find_by(id: params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if delegation.nil?

    save_and_return_updated(delegation, revocation_params.merge(status: "revoked"), "delegation_revoked")
  end

  # A new version is a copy, so the approved one stays exactly as approved while
  # the next is consulted over — and so the two can be compared.
  def open_next_version
    successor = AuthorityMatrixVersionService.open_next(@matrix, actor: current_user)
    redirect_to dashboard_authorities_path(matrix_id: successor.id),
      notice: t("doa.versions.opened"), status: :see_other
  end

  def create_consultation
    consultation = @matrix.consultations.new(consultation_params)
    consultation.raised_by = current_user

    save_and_return(consultation, "consultation_created")
  end

  def rule_consultation
    consultation = @matrix.consultations.find_by(id: params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if consultation.nil?

    save_and_return_updated(consultation, consultation_ruling_params, "consultation_ruled")
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

    # An authority starts with one "all amounts" band so it has somewhere to
    # hang holders. The first thresholds a user enters bound that band rather
    # than colliding with it — which is what made every band submission vanish
    # into an overlap error.
    placeholder = authority.bands.first if authority.bands.one? && !authority.bands.first.bounded?
    if placeholder
      return save_and_return_updated(placeholder, band_params, "band_created")
    end

    band = authority.bands.new(band_params)
    band.sort_order = authority.bands.maximum(:sort_order).to_i + 1

    save_and_return(band, "band_created")
  end

  def update_band
    band = matrix_band(params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if band.nil?

    save_and_return_updated(band, band_params, "band_updated")
  end

  # A band's holders go with it. An authority always keeps at least one band.
  def destroy_band
    band = matrix_band(params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if band.nil?
    return back_to_matrix(alert: t("doa.flash.last_band")) if band.authority.bands.one?

    band.destroy
    back_to_matrix(notice: t("doa.flash.deleted"))
  end

  def update_category
    category = company.authority_categories.find_by(id: params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if category.nil?

    save_and_return_updated(category, category_params, "category_updated")
  end

  # Authorities in a removed category are kept, uncategorised, rather than
  # deleted along with a heading.
  def destroy_category
    company.authority_categories.find_by(id: params[:id])&.destroy
    back_to_matrix(notice: t("doa.flash.deleted"))
  end

  def update_authority
    authority = @matrix.authorities.find_by(id: params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if authority.nil?

    save_and_return_updated(authority, authority_params, "authority_updated")
  end

  # One box per level. The holder arrives as a single tagged value —
  # "unit:<id>", "user:<id>" or "role:<key>" — from one searchable list, so a
  # user picks from units and people together without knowing the model.
  def create_assignment
    band = matrix_band(params[:band_id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if band.nil?

    attributes = assignment_params.to_h.merge(holder_attributes(params[:holder]))
    save_and_return(band.assignments.new(attributes), "assignment_created")
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

  def matrix_band(id)
    AuthorityBand.joins(:authority).where(authorities: { matrix_id: @matrix.id }).find_by(id: id)
  end

  # Decodes the holder picker's value into the column it belongs in.
  def holder_attributes(value)
    kind, id = value.to_s.split(":", 2)
    case kind
    when "unit" then { org_unit_id: id }
    when "user" then { user_id: id }
    when "role" then { dynamic_role: id }
    else {}
    end
  end

  def save_and_return_updated(record, attributes, flash_key)
    record.assign_attributes(attributes)
    save_and_return(record, flash_key)
  end

  def save_and_return(record, flash_key)
    if record.save
      back_to_matrix(notice: t("doa.flash.#{flash_key}"))
    else
      retain_form_values(record.model_name.param_key, retained_attributes_for(record))
      back_to_matrix(alert: record.errors.full_messages.to_sentence)
    end
  end

  # What the form would need to show again: the typed columns, plus which
  # parent the row was meant for.
  def retained_attributes_for(record)
    typed = record.attributes.reject { |k, v| v.nil? || %w[id created_at updated_at sort_order].include?(k) }
    typed["holder"] = params[:holder] if params[:holder].present?
    typed
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

  def delegation_params
    params.require(:authority_delegation).permit(:authority_id, :from_org_unit_id, :to_org_unit_id,
      :kind, :limit_amount, :valid_from, :valid_to, :status, :decision_record_id,
      :parent_delegation_id, :reason)
  end

  def revocation_params
    params.require(:authority_delegation).permit(:revocation_reason)
  end

  def consultation_params
    params.require(:authority_consultation).permit(:authority_id, :org_unit_id, :challenge,
      :proposal, :expected_impact)
  end

  def consultation_ruling_params
    params.require(:authority_consultation).permit(:status, :ruling)
  end

  def assignment_params
    params.require(:authority_assignment).permit(:level, :holder_title, :condition)
  end
end
