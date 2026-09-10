class Dashboard::PpRecordsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [
    :new, :create, :edit, :update, :destroy, :attach_documents, :detach_document, :open_next_version
  ]
  before_action :set_record, only: [
    :show, :edit, :update, :destroy, :attach_documents, :detach_document, :document, :document_docx, :open_next_version
  ]
  before_action :ensure_editable, only: [ :edit, :update, :destroy ]
  before_action :ensure_version_visible, only: [ :show, :document, :document_docx ]

  helper_method :can_manage_pp_records?, :can_see_versions?

  def index
    # The executive authority matrix is a record, but it lives on its own page.
    scope = company_scope.where.not(record_type: "executive_doa").includes(:owner_user, :owner_org_unit, :pp_process, :package)
    @show_inactive = params[:show_inactive] == "1"
    scope = scope.active unless @show_inactive

    # One tab per record type; "all" shows everything.
    @record_type = params[:record_type].presence
    scope = scope.of_type(@record_type) if @record_type && PpRecord::TYPES.include?(@record_type)

    # Everyone sees the latest issue of each document. Quality managers and
    # admins may also list the earlier versions.
    @show_versions = can_see_versions? && params[:show_versions] == "1"
    scope = scope.latest unless @show_versions

    @query = params[:q].to_s.strip
    if @query.present?
      like = "%#{@query}%"
      scope = scope.where(
        "pp_records.title_en ILIKE :q OR pp_records.title_ar ILIKE :q OR pp_records.code ILIKE :q", q: like
      )
    end

    @records = scope.ordered.to_a
    @counts_by_type = company_scope.active.latest.group(:record_type).count
    @total_count = company_scope.active.latest.where.not(record_type: "executive_doa").count
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

  # The same document as a Word file, built from the same sections, so the two
  # cannot describe different things.
  def document_docx
    renderer = RecordDocxRenderer.new(RecordDocument.new(@record, locale: I18n.locale))

    send_data renderer.render,
      filename: renderer.filename,
      type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      disposition: "attachment"
  end

  def show
    @attachments = @record.evidence_attachments.includes(upload: :folder).order(created_at: :desc)
    @folders_for_upload = company.folders.order(:name)
    @available_uploads = company.uploads.where.not(id: @attachments.map(&:upload_id)).includes(:folder).order(created_at: :desc).limit(100)
  end

  # The type comes from the tab the button was pressed on; it is not chosen
  # inside the form.
  def new
    # The authority matrices are built on their own page, never through this form.
    if PpRecord::DOA_TYPES.include?(params[:record_type])
      return redirect_to dashboard_authorities_path, notice: t("pp_records.flash.doa_lives_in_authorities"), status: :see_other
    end

    type = PpRecord::TAB_TYPES.include?(params[:record_type]) ? params[:record_type] : PpRecord::TAB_TYPES.first
    @record = company_scope.new(record_type: type)
    render_form
  end

  # "Update existing": opens the next version as a draft carrying everything
  # the current one says, and asks for the reason for change.
  def open_next_version
    unless @record.latest_version?
      redirect_to dashboard_pp_record_path(@record.next_version), alert: t("pp_records.flash.already_updated"), status: :see_other
      return
    end

    successor = RecordVersionService.open_next(@record, actor: current_user)
    @record = successor
    log_action("OPEN_NEXT_VERSION")
    redirect_to edit_dashboard_pp_record_path(successor), notice: t("pp_records.flash.next_version_opened", version: successor.version_number), status: :see_other
  end

  def edit
    render_form
  end

  def create
    @record = company_scope.new(record_params)
    @record.company = company

    if @record.save
      save_links_and_participants
      log_action("CREATE_PP_RECORD")
      redirect_to dashboard_pp_record_path(@record), notice: t("pp_records.flash.created"), status: :see_other
    else
      render_form(status: :unprocessable_entity)
    end
  end

  def update
    if @record.update(record_params)
      save_links_and_participants
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

  # The admin, the quality managers, and the admin's own team (see
  # RecordAuthoring).
  def can_manage_pp_records?
    RecordAuthoring.allowed?(current_user, company)
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

  # Multi-picks arrive as id lists and are written as link rows, so the record
  # form stays a plain form.
  def save_links_and_participants
    if @record.procedure?
      replace_links("related_policy", params[:related_policy_ids])
      replace_links("form_used", params[:form_used_ids])
    end
    return unless @record.service?

    wanted = Array(params[:participating_unit_ids]).reject(&:blank?)
    wanted &= company.org_units.where(id: wanted).pluck(:id)
    @record.participants.where.not(org_unit_id: wanted).destroy_all
    (wanted - @record.participants.pluck(:org_unit_id)).each { |id| @record.participants.create!(org_unit_id: id) }
  end

  def replace_links(kind, ids)
    wanted = Array(ids).reject(&:blank?)
    wanted &= company_scope.where(id: wanted).pluck(:id)
    @record.links.of_kind(kind).where.not(linked_record_id: wanted).destroy_all
    existing = @record.links.of_kind(kind).pluck(:linked_record_id)
    (wanted - existing).each { |id| @record.links.create!(linked_record_id: id, kind: kind) }
  end

  def render_form(status: :ok)
    @org_units = company.org_units.active.ordered.to_a
    @company_users = company.users.order(:name).to_a
    @processes = company.pp_processes.active.ordered.to_a
    latest = company_scope.active.latest.ordered
    @policies = latest.of_type("policy").to_a
    @forms = latest.of_type("form").to_a
    @procedures = latest.of_type("procedure").where.not(id: @record.id).to_a
    render(@record&.persisted? ? :edit : :new, status: status)
  end

  # Published records are read-only; their next version is where changes go.
  def ensure_editable
    return if @record.editable?

    redirect_to dashboard_pp_record_path(@record), alert: t("pp_records.flash.read_only"), status: :see_other
  end

  # Earlier versions are history for the quality team; everyone else lands on
  # the latest issue.
  def ensure_version_visible
    return if @record.latest_version? || can_see_versions?

    latest = @record
    latest = latest.next_version while latest.next_version
    redirect_to dashboard_pp_record_path(latest), status: :see_other
  end

  def can_see_versions?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  # A record never chooses its own package — that is composed from the package
  # side — so package_id is deliberately NOT permitted here.
  def record_params
    params.require(:pp_record).permit(
      :record_type, :title_en, :title_ar, :description, :scope, :verifier_user_id,
      :effective_date, :review_date, :owner_user_id, :owner_org_unit_id,
      :pp_process_id, :active, :classification, :counterparty, :change_summary,
      :trigger_text, :inputs, :outputs, :predecessor_record_id, :successor_record_id,
      :frequency, :total_time_value, :total_time_unit, :automation_status, :technical_systems, :kpis,
      :service_type, :requirements, :beneficiaries, :delivery_period, :channels, :delivery_stages,
      :counterparty_kind, :counterparty_org_unit_id
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
