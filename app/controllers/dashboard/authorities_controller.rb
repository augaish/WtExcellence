# The executive authority matrix: the authorities a company's Executive DoA
# grants, the thresholds they are split by, and who holds each level.
class Dashboard::AuthoritiesController < Dashboard::BaseController
  requires_module :authorities
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, except: [ :index, :answer_review, :download_pdf, :create_review_comment ]
  before_action :set_matrix
  before_action :ensure_matrix_present, except: [ :index, :create_category, :apply_suggestions, :import, :run_import, :template ]
  # Only the newest version can change; an older one is read on its own terms.
  before_action :ensure_matrix_editable, except: [ :index, :answer_review, :download_pdf, :create_category,
    :apply_suggestions, :import, :run_import, :template, :open_next_version, :create_delegation, :revoke_delegation,
    :create_review_comment ]

  helper_method :can_manage_authorities?, :can_edit_matrix?, :company_admin?, :can_comment_on_matrix?

  def index
    @suggested_categories = AuthorityCatalogue.categories
    @company_users = company.users.order(:name).to_a
    return if @matrix.nil?

    @report = AuthorityMatrixReport.new(@matrix)
    @authorities = @report.authorities
    @categories = company.authority_categories.to_a
    @org_units = company.org_units.active.ordered.to_a
    @company_users = company.users.order(:name).to_a
    @diff = AuthorityMatrixDiff.new(@matrix.previous_version, @matrix) if @matrix.previous_version
    @numbers = Authority.numbered(@authorities)
    @review_comments = @matrix.review_comments.includes(:user, :replied_by).ordered.group_by(&:authority_id)
    @suggested_categories = AuthorityCatalogue.categories
    @delegations = company.authority_delegations
      .includes(:authority, :from_org_unit, :to_org_unit, :parent_delegation).to_a
    @reviews = @matrix.matrix_reviews.includes(:user).ordered.to_a
    @my_review = @reviews.find { |r| r.user_id == current_user.id && r.pending? }
    @has_changes = @diff ? @diff.any? : @authorities.any?
    @published_version = company.pp_records.of_type("executive_doa").where(current_stage: PpStage::TERMINAL_KEYS)
      .order(version_number: :desc).first
  end

  # Suggestions are applied only when asked for, and become ordinary editable
  # records — never seeded data the company did not choose.
  def apply_suggestions
    keys = Array(params[:category_keys]).map(&:to_s)
    return back_to_matrix(alert: t("doa.catalogue.none_selected")) if keys.empty?

    @matrix ||= AuthorityMatrixVersionService.first_version(company, actor: current_user)

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

  # The Governance Manager or admin picks people to look over the changes.
  # Every one of them must accept before the admin can publish.
  def send_for_review
    ids = Array(params[:user_ids]).reject(&:blank?)
    users = company.users.where(id: ids).to_a
    return back_to_matrix(alert: t("doa.review.pick_someone")) if users.empty?

    users.each do |user|
      review = @matrix.matrix_reviews.find_or_initialize_by(user: user)
      review.assign_attributes(requested_by: current_user, requested_at: Time.current, decision: nil, comment: nil, decided_at: nil)
      review.save!
      Notification.create!(recipient: user, source: @matrix, kind: "authority_review_requested",
        title: I18n.t("user_notifications.authority_review_requested_title", actor_name: current_user.name),
        link_path: dashboard_authorities_path(matrix_id: @matrix.id), payload: { matrix_id: @matrix.id })
    end
    back_to_matrix(notice: t("doa.review.sent", count: users.size))
  end

  def answer_review
    review = @matrix.matrix_reviews.find_by(id: params[:id], user_id: current_user.id)
    return back_to_matrix(alert: t("doa.flash.not_found")) if review.nil? || !review.pending?
    return back_to_matrix(alert: t("doa.review.comment_required")) if params[:decision] == "rejected" && params[:comment].to_s.strip.blank?

    review.answer!(params[:decision] == "accepted" ? "accepted" : "rejected", comment: params[:comment])
    back_to_matrix(notice: t("doa.review.answered"))
  end

  # The company admin makes the version take effect once everyone accepted.
  def publish
    return back_to_matrix(alert: t("doa.flash.no_permission")) unless company_admin?
    return back_to_matrix(alert: t("doa.review.not_all_accepted")) unless @matrix.matrix_reviews.any? && @matrix.matrix_reviews.pending.none? && @matrix.matrix_reviews.rejected.none?

    @matrix.update!(current_stage: PpStage::TERMINAL_KEYS.first, stage_entered_at: Time.current, published_at: Time.current)
    back_to_matrix(notice: t("doa.review.published", version: @matrix.version_number))
  end

  # The matrix as a file. Chromium prints it where it is installed; otherwise
  # the print-ready page opens for the browser's own "Save as PDF".
  def download_pdf
    pdf = RecordPdfRenderer.new(@matrix, locale: I18n.locale)
    bytes = pdf.render
    if bytes
      send_data bytes, filename: pdf.filename, type: "application/pdf", disposition: "attachment"
    else
      redirect_to document_dashboard_pp_record_path(@matrix), status: :see_other
    end
  end

  # A new version is a copy, so the approved one stays exactly as approved while
  # the next is consulted over — and so the two can be compared.
  def open_next_version
    successor = AuthorityMatrixVersionService.open_next(@matrix, actor: current_user)
    redirect_to dashboard_authorities_path(matrix_id: successor.id),
      notice: t("doa.versions.opened"), status: :see_other
  end

  # A reviewer writes a note against one authority; the owner answers it.
  def create_review_comment
    return back_to_matrix(alert: t("doa.flash.no_permission")) unless can_comment_on_matrix?
    return back_to_matrix(alert: t("doa.errors.matrix_published")) unless @matrix.latest_version?

    authority = @matrix.authorities.find_by(id: params[:authority_id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if authority.nil?

    comment = @matrix.review_comments.new(authority: authority, user: current_user, body: params[:body])
    save_and_return(comment, "comment_added")
  end

  def answer_review_comment
    comment = @matrix.review_comments.find_by(id: params[:id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if comment.nil?

    attributes = { decision: params[:decision], reply: params[:reply], replied_by: current_user, replied_at: Time.current }
    save_and_return_updated(comment, attributes, "comment_answered")
  end

  # The page starts empty; the first category brings the matrix into being.
  def create_category
    @matrix ||= AuthorityMatrixVersionService.first_version(company, actor: current_user)
    category = company.authority_categories.new(category_params)

    save_and_return(category, "category_created")
  end

  # Drag order from the page: ids in the order they now sit.
  def reorder_categories
    ids = Array(params[:ids]).reject(&:blank?)
    company.authority_categories.where(id: ids).each do |category|
      category.update_columns(sort_order: ids.index(category.id) + 1)
    end
    head :no_content
  end

  def create_authority
    authority = company.authorities.new(authority_params)
    authority.matrix = @matrix
    authority.number = (@matrix.authorities.maximum(:number).to_i + 1)
    authority.sort_order = authority.number

    save_and_return(authority, "authority_created")
  end

  # Drag order inside one category, or a row dropped into another category:
  # the ids in the order they now sit, and the category they sit in.
  def reorder_authorities
    ids = Array(params[:ids]).reject(&:blank?)
    category = company.authority_categories.find_by(id: params[:category_id])
    @matrix.authorities.where(id: ids).each do |authority|
      authority.update_columns(sort_order: ids.index(authority.id) + 1, authority_category_id: category&.id)
    end
    head :no_content
  end

  # ---- Import from Excel ---------------------------------------------------

  def import
    @result = nil
  end

  def run_import
    file = params[:file]
    if file.blank?
      @result = AuthorityImportService::Result.new(categories: 0, authorities: 0, errors: [ { row: 0, message: t("doa.import.no_file") } ])
      return render :import, status: :unprocessable_entity
    end

    @matrix ||= AuthorityMatrixVersionService.first_version(company, actor: current_user)
    @result = AuthorityImportService.import(file: file, matrix: @matrix)
    if @result.success?
      redirect_to dashboard_authorities_path(matrix_id: @matrix.id),
        notice: t("doa.import.done", categories: @result.categories, authorities: @result.authorities), status: :see_other
    else
      render :import, status: :unprocessable_entity
    end
  end

  # The workbook to fill in: one row per authority, one column per level, and
  # every holder column offers the company's units and people as a dropdown.
  def template
    send_data AuthorityImportTemplate.new(company).to_xlsx,
      filename: "authorities_template.xlsx",
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
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
    authority = @matrix.authorities.find_by(id: params[:authority_id])
    return back_to_matrix(alert: t("doa.flash.not_found")) if authority.nil?

    attributes = assignment_params.to_h.merge(holder_attributes(params[:holder]))
    save_and_return(authority.default_band.assignments.new(attributes), "assignment_created")
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

  def ensure_matrix_present
    return if @matrix

    redirect_to dashboard_authorities_path, alert: t("doa.no_matrix"), status: :see_other
  end

  def ensure_matrix_editable
    return if can_edit_matrix?

    back_to_matrix(alert: t("doa.errors.matrix_published"))
  end

  # The matrix being viewed: the one asked for, or the company's most recent.
  def set_matrix
    matrices = company.pp_records.of_type("executive_doa").order(version_number: :desc, created_at: :desc)
    @matrices = matrices.to_a
    @matrix = params[:matrix_id].present? ? matrices.find_by(id: params[:matrix_id]) : matrices.first
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

  # The company admin and the Governance Managers run this page; everyone
  # else reads it.
  def can_manage_authorities?
    return true if current_user&.platform_admin?

    membership = current_user&.company_user
    membership.present? && (membership.company_admin? || membership.gov_manager?)
  end

  # Editing needs the newest version on screen: an older one is a statement of
  # record, whether or not it was ever published.
  def can_edit_matrix?
    can_manage_authorities? && @matrix.present? && @matrix.latest_version?
  end

  # Reviewers of this version and the people who manage the matrix.
  def can_comment_on_matrix?
    return false if @matrix.nil?
    return true if can_manage_authorities?

    @matrix.matrix_reviews.exists?(user_id: current_user.id)
  end

  def company_admin?
    current_user&.platform_admin? || current_user&.company_user&.company_admin? || false
  end

  def ensure_can_manage
    return if can_manage_authorities?

    redirect_to dashboard_authorities_path, alert: t("doa.flash.no_permission"), status: :see_other
  end

  def category_params
    params.require(:authority_category).permit(:code, :name_en, :name_ar)
  end

  def authority_params
    params.require(:authority).permit(:authority_category_id, :name_en, :name_ar, :notes, :conflict_sensitive)
  end

  def delegation_params
    params.require(:authority_delegation).permit(:authority_id, :from_org_unit_id, :to_org_unit_id,
      :kind, :limit_amount, :valid_from, :valid_to, :status, :decision_record_id,
      :parent_delegation_id, :reason)
  end

  def revocation_params
    params.require(:authority_delegation).permit(:revocation_reason)
  end

  def assignment_params
    params.require(:authority_assignment).permit(:level, :holder_title, :condition)
  end
end
