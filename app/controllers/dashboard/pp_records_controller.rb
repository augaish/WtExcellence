class Dashboard::PpRecordsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [
    :new, :create, :edit, :update, :destroy, :attach_documents, :detach_document
  ]
  before_action :set_record, only: [ :show, :edit, :update, :destroy, :attach_documents, :detach_document, :document ]

  helper_method :can_manage_pp_records?

  def index
    scope = company_scope.includes(:owner_user, :owner_org_unit, :pp_process, :package)
    @show_inactive = params[:show_inactive] == "1"
    scope = scope.active unless @show_inactive

    # One tab per record type; "all" shows everything.
    @record_type = params[:record_type].presence
    scope = scope.of_type(@record_type) if @record_type && PpRecord::TYPES.include?(@record_type)

    @query = params[:q].to_s.strip
    if @query.present?
      like = "%#{@query}%"
      scope = scope.where(
        "pp_records.title_en ILIKE :q OR pp_records.title_ar ILIKE :q OR pp_records.code ILIKE :q", q: like
      )
    end

    @records = scope.ordered.to_a
    @counts_by_type = company_scope.active.group(:record_type).count
    @total_count = company_scope.active.count
    @packages_count = company.pp_packages.count
    @due_for_review = company_scope.active.where.not(review_date: nil)
      .select { |r| r.review_overdue? || r.review_due_soon?(review_lead_days) }
  end

  # The governed document itself, assembled from the record and rendered with the
  # company's branding. Laid out for print, so the browser's own "Save as PDF"
  # produces the file — no headless browser on the server, which this deployment
  # cannot afford to run.
  def document
    @document = RecordDocument.new(@record, locale: I18n.locale)
    render layout: "document"
  end

  def show
    @attachments = @record.evidence_attachments.includes(:upload).order(created_at: :desc)
    @folders_for_upload = company.folders.order(:name)
    @available_uploads = company.uploads.where.not(id: @attachments.map(&:upload_id)).order(created_at: :desc).limit(100)
  end

  def new
    @record = company_scope.new(
      record_type: params[:record_type].presence || PpRecord::TYPES.first,
      code: suggested_code
    )
    render_form
  end

  def edit
    render_form
  end

  def create
    @record = company_scope.new(record_params)
    @record.company = company
    @record.code = suggested_code if @record.code.blank?

    if @record.save
      log_action("CREATE_PP_RECORD")
      redirect_to dashboard_pp_record_path(@record), notice: t("pp_records.flash.created"), status: :see_other
    else
      render_form(status: :unprocessable_entity)
    end
  end

  def update
    if @record.update(record_params)
      log_action("UPDATE_PP_RECORD")
      redirect_to dashboard_pp_record_path(@record), notice: t("pp_records.flash.updated"), status: :see_other
    else
      render_form(status: :unprocessable_entity)
    end
  end

  def destroy
    @record.destroy
    log_action("DELETE_PP_RECORD")
    redirect_to dashboard_pp_records_path, notice: t("pp_records.flash.deleted"), status: :see_other
  end

  # Attach documents either by uploading new files (which land in the Library,
  # in a per-type P&P folder) or by linking files that are already there.
  def attach_documents
    linked = 0

    Array(params[:upload_ids]).reject(&:blank?).each do |upload_id|
      upload = company.uploads.find_by(id: upload_id)
      next if upload.nil?
      next if @record.evidence_attachments.exists?(upload_id: upload.id)

      @record.evidence_attachments.create!(upload: upload, attached_by: current_user&.id)
      linked += 1
    end

    Array(params[:files]).reject(&:blank?).each do |file|
      upload = PpRecordDocumentService.upload_into_library(
        file: file, record: @record, company: company, user: current_user
      )
      next if upload.nil?

      @record.evidence_attachments.create!(upload: upload, attached_by: current_user&.id)
      linked += 1
    end

    log_action("ATTACH_PP_RECORD_DOCUMENTS")
    redirect_to dashboard_pp_record_path(@record),
      notice: t("pp_records.flash.documents_attached", count: linked), status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_pp_record_path(@record), alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def detach_document
    attachment = @record.evidence_attachments.find_by(upload_id: params[:upload_id])
    attachment&.destroy
    log_action("DETACH_PP_RECORD_DOCUMENT")
    redirect_to dashboard_pp_record_path(@record), notice: t("pp_records.flash.document_detached"), status: :see_other
  end

  private

  def company
    @company ||= current_company
  end

  def company_scope
    company.pp_records
  end

  def review_lead_days
    30
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("pp_records.flash.no_company"), status: :see_other
  end

  def can_manage_pp_records?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_pp_records?

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.no_permission"), status: :see_other
  end

  def set_record
    @record = company_scope.find_by(id: params[:id])
    return if @record

    redirect_to dashboard_pp_records_path, alert: t("pp_records.flash.not_found"), status: :see_other
  end

  def suggested_code
    HierarchicalCodeService.next_record_code(
      company: company, record_type: params.dig(:pp_record, :record_type) || params[:record_type]
    )
  end

  def render_form(status: :ok)
    @org_units = company.org_units.active.ordered.to_a
    @company_users = company.users.order(:name).to_a
    @processes = company.pp_processes.active.ordered.to_a
    render(@record&.persisted? ? :edit : :new, status: status)
  end

  # A record never chooses its own package — that is composed from the package
  # side — so package_id is deliberately NOT permitted here.
  def record_params
    params.require(:pp_record).permit(
      :record_type, :code, :title_en, :title_ar, :description, :version_label,
      :effective_date, :review_date, :owner_user_id, :owner_org_unit_id,
      :pp_process_id, :active, :classification, :counterparty
    )
  end

  def log_action(action)
    AuditLogService.log_action(
      actor_user: current_user, company: company, action: action,
      entity_type: "pp_record", entity_id: @record&.id,
      payload: { code: @record&.code, title: @record&.display_title }
    )
  end
end
