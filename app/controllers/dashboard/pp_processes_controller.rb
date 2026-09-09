class Dashboard::PpProcessesController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [
    :new, :create, :edit, :update, :destroy, :toggle_active, :import, :run_import,
    :settings, :update_settings
  ]
  before_action :set_process, only: [ :show, :edit, :update, :destroy, :toggle_active ]

  helper_method :can_manage_processes?

  def index
    scope = company_scope.includes(:owner_org_unit, :owner_user, :parent)
    @show_inactive = params[:show_inactive] == "1"
    scope = scope.active unless @show_inactive

    @category = params[:category].presence
    scope = scope.where(category: @category) if @category && PpProcess::CATEGORIES.include?(@category)

    @query = params[:q].to_s.strip
    if @query.present?
      like = "%#{@query}%"
      scope = scope.where(
        "pp_processes.name_en ILIKE :q OR pp_processes.name_ar ILIKE :q OR pp_processes.code ILIKE :q", q: like
      )
    end

    @processes = scope.ordered.to_a
    @by_parent = @processes.group_by(&:parent_id)
    @roots = @by_parent[nil] || []
    @total_count = company_scope.count
    @level_counts = company_scope.group(:level).count

    # Two pictures of the same tree: the list, and the model with its bands.
    @view = params[:view] == "model" ? "model" : "list"
    @by_band = @roots.group_by(&:effective_category)
  end

  # Level 0 names and the objective shown beside the model.
  def settings
  end

  def update_settings
    names = params.fetch(:band_names, {}).permit!.to_h.slice(*PpProcess::CATEGORIES)
    names = names.transform_values { |v| { "en" => v["en"].to_s.strip, "ar" => v["ar"].to_s.strip } }

    if company.update(process_band_names: names,
                      process_objective_en: params[:process_objective_en].to_s.strip,
                      process_objective_ar: params[:process_objective_ar].to_s.strip)
      redirect_to dashboard_pp_processes_path(view: "model"), notice: t("process_architecture.flash.settings_saved"), status: :see_other
    else
      flash.now[:alert] = company.errors.full_messages.to_sentence
      render :settings, status: :unprocessable_entity
    end
  end

  # The procedure's own detail: its steps and its operational authority matrix.
  # Both become sections of the generated document, so they are edited on a
  # page of their own rather than in the drawer used for the process card.
  def show
    @steps = @process.steps.includes(:responsible_org_unit).to_a
    @authorities = @process.authorities.includes(assignments: :org_unit).to_a
    @org_units = company.org_units.active.ordered.to_a

    # The operational matrix must stay consistent with the executive one; today
    # that is a person reading two spreadsheets side by side.
    @conformance = AuthorityConformanceCheck.new(@process)
    @executive_authorities = company.authorities
      .where(matrix_id: company.pp_records.of_type("executive_doa").select(:id)).ordered.to_a
  end

  def new
    # Reached from the "+" on Level 1 or Level 2, or from a parent's row.
    parent = company_scope.find_by(id: params[:parent_id].presence)
    level = parent ? 2 : params[:level].to_i.clamp(1, PpProcess::MAX_LEVEL)
    @process = company_scope.new(
      parent_id: parent&.id,
      level: level,
      category: parent&.effective_category || params[:category].presence
    )
    render_drawer
  end

  def edit
    render_drawer
  end

  def create
    @process = company_scope.new(process_params)
    @process.company = company

    if @process.save
      log_action("CREATE_PROCESS")
      redirect_to dashboard_pp_processes_path, notice: t("process_architecture.flash.created"), status: :see_other
    else
      render_drawer(status: :unprocessable_entity)
    end
  end

  def update
    if @process.update(process_params)
      log_action("UPDATE_PROCESS")
      redirect_to dashboard_pp_processes_path, notice: t("process_architecture.flash.updated"), status: :see_other
    else
      render_drawer(status: :unprocessable_entity)
    end
  end

  def destroy
    if @process.children.exists?
      redirect_to dashboard_pp_processes_path, alert: t("process_architecture.flash.has_children"), status: :see_other
      return
    end

    if @process.destroy
      log_action("DELETE_PROCESS")
      redirect_to dashboard_pp_processes_path, notice: t("process_architecture.flash.deleted"), status: :see_other
    else
      redirect_to dashboard_pp_processes_path,
        alert: @process.errors.full_messages.to_sentence.presence || t("process_architecture.flash.delete_failed"),
        status: :see_other
    end
  end

  def toggle_active
    @process.update(active: !@process.active)
    log_action(@process.active? ? "ACTIVATE_PROCESS" : "DEACTIVATE_PROCESS")
    redirect_to dashboard_pp_processes_path, notice: t("process_architecture.flash.updated"), status: :see_other
  end

  def import
    @result = nil
  end

  def run_import
    file = params[:file]
    if file.blank?
      @result = PpProcessImportService::Result.new(created: 0, updated: 0, errors: [ { row: 0, message: t("process_architecture.import.no_file") } ])
      return render :import, status: :unprocessable_entity
    end

    @result = PpProcessImportService.import(file: file, company: company)
    if @result.success?
      log_action("IMPORT_PROCESSES")
      redirect_to dashboard_pp_processes_path,
        notice: t("process_architecture.import.done", created: @result.created, updated: @result.updated),
        status: :see_other
    else
      render :import, status: :unprocessable_entity
    end
  end

  def template
    send_data PpProcessImportService.template_csv,
      filename: "process_architecture_template.csv", type: "text/csv"
  end

  private

  def company
    @company ||= current_company
  end

  def company_scope
    company.pp_processes
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("process_architecture.flash.no_company"), status: :see_other
  end

  def can_manage_processes?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_processes?

    redirect_to dashboard_pp_processes_path, alert: t("process_architecture.flash.no_permission"), status: :see_other
  end

  def set_process
    @process = company_scope.find_by(id: params[:id])
    return if @process

    redirect_to dashboard_pp_processes_path, alert: t("process_architecture.flash.not_found"), status: :see_other
  end

  def render_drawer(status: :ok)
    @parent_options = company_scope.active.where(level: 1).ordered.to_a
    @parent_options -= [ @process ] if @process&.persisted?
    @org_units = company.org_units.active.ordered.to_a
    @company_users = company.users.order(:name).to_a
    @link_options = company_scope.active.ordered.to_a
    @link_options -= [ @process ] if @process&.persisted?
    render(@process&.persisted? ? :edit : :new, status: status)
  end

  def process_params
    params.require(:pp_process).permit(
      :parent_id, :level, :category, :code, :name_en, :name_ar, :objective,
      :owner_org_unit_id, :owner_user_id, :trigger_text, :inputs, :outputs,
      :predecessor_process_id, :successor_process_id, :frequency,
      :total_time_value, :total_time_unit, :automation_status,
      :related_policies, :technical_systems, :forms_used, :kpis,
      :sort_order, :active
    )
  end

  def log_action(action)
    AuditLogService.log_action(
      actor_user: current_user,
      company: company,
      action: action,
      entity_type: "pp_process",
      entity_id: @process&.id,
      payload: { code: @process&.code, name: @process&.display_name }
    )
  rescue => e
    Rails.logger.warn "PpProcesses audit log failed: #{e.class}: #{e.message}"
  end
end
