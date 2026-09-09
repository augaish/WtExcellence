class Dashboard::OrgUnitsController < Dashboard::BaseController
  requires_module :org_structure
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [
    :new, :create, :edit, :update, :destroy, :toggle_active,
    :import, :run_import, :settings, :update_settings, :build_library
  ]
  before_action :set_org_unit, only: [ :edit, :update, :destroy, :toggle_active ]

  helper_method :can_manage_org_structure?

  def index
    scope = company_scope.includes(:org_group, :head_user, :parent)
    @show_inactive = params[:show_inactive] == "1"
    scope = scope.active unless @show_inactive

    @query = params[:q].to_s.strip
    if @query.present?
      like = "%#{@query}%"
      scope = scope.where(
        "org_units.name_en ILIKE :q OR org_units.name_ar ILIKE :q OR org_units.code ILIKE :q", q: like
      )
    end

    @units = scope.ordered.to_a
    @units_by_parent = @units.group_by(&:parent_id)
    @roots = @units_by_parent[nil] || []
    @level_definitions = company.org_level_definitions.ordered.to_a
    @groups = company.org_groups.ordered.to_a
    @total_count = company_scope.count
  end

  # The chart view: the same structure as the list, drawn as connected boxes
  # coloured by group, with each unit's mandate a click away.
  def chart
    scope = company_scope.includes(:org_group, :head_user)
    scope = scope.active unless params[:show_inactive] == "1"
    @units = scope.order(:level, :sort_order, :name_en).to_a
    @groups = company.org_groups.to_a
    @show_inactive = params[:show_inactive] == "1"
  end

  # Builds (or refreshes) the Library folders that mirror the structure.
  def build_library
    result = OrgLibraryBuilder.build(company, user: current_user)
    log_action("build_library")
    redirect_to dashboard_org_units_path,
      notice: t("org_structure.flash.library_built", created: result.created, updated: result.updated),
      status: :see_other
  end

  def new
    @org_unit = company_scope.new(
      parent_id: params[:parent_id].presence,
      level: default_level_for(params[:parent_id].presence),
      code: suggested_code(params[:parent_id].presence)
    )
    render_drawer
  end

  def edit
    render_drawer
  end

  def create
    @org_unit = company_scope.new(org_unit_params)
    @org_unit.company = company
    @org_unit.code = suggested_code(@org_unit.parent_id) if @org_unit.code.blank?

    if @org_unit.save
      log_action("CREATE_ORG_UNIT")
      redirect_to dashboard_org_units_path, notice: t("org_structure.flash.created"), status: :see_other
    else
      render_drawer(status: :unprocessable_entity)
    end
  end

  def update
    if @org_unit.update(org_unit_params)
      log_action("UPDATE_ORG_UNIT")
      redirect_to dashboard_org_units_path, notice: t("org_structure.flash.updated"), status: :see_other
    else
      render_drawer(status: :unprocessable_entity)
    end
  end

  def destroy
    if @org_unit.children.exists?
      redirect_to dashboard_org_units_path, alert: t("org_structure.flash.has_children"), status: :see_other
      return
    end

    if @org_unit.destroy
      log_action("DELETE_ORG_UNIT")
      redirect_to dashboard_org_units_path, notice: t("org_structure.flash.deleted"), status: :see_other
    else
      redirect_to dashboard_org_units_path,
        alert: @org_unit.errors.full_messages.to_sentence.presence || t("org_structure.flash.delete_failed"),
        status: :see_other
    end
  end

  def toggle_active
    @org_unit.update(active: !@org_unit.active)
    log_action(@org_unit.active? ? "ACTIVATE_ORG_UNIT" : "DEACTIVATE_ORG_UNIT")
    redirect_to dashboard_org_units_path, notice: t("org_structure.flash.updated"), status: :see_other
  end

  # --- Structure settings: level names + colour groups ---------------------
  def settings
    @level_definitions = (1..OrgLevelDefinition::MAX_LEVEL).map do |level|
      company.org_level_definitions.detect { |d| d.level == level } ||
        company.org_level_definitions.new(level: level)
    end
    @groups = company.org_groups.ordered.to_a
  end

  def update_settings
    submitted = params.fetch(:levels, {}).permit!.to_h

    ActiveRecord::Base.transaction do
      submitted.each do |level, attrs|
        level_number = level.to_i
        next unless level_number.between?(1, OrgLevelDefinition::MAX_LEVEL)

        definition = company.org_level_definitions.find_or_initialize_by(level: level_number)
        definition.name_en = attrs["name_en"].to_s.strip.presence
        definition.name_ar = attrs["name_ar"].to_s.strip.presence

        if definition.name_en.blank? && definition.name_ar.blank?
          definition.destroy if definition.persisted?
        else
          definition.save!
        end
      end
    end
    log_action("UPDATE_ORG_LEVELS")
    redirect_to settings_dashboard_org_units_path, notice: t("org_structure.flash.settings_saved"), status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_dashboard_org_units_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # --- Import --------------------------------------------------------------
  def import
    @result = nil
  end

  def run_import
    file = params[:file]
    if file.blank?
      @result = OrgUnitImportService::Result.new(created: 0, updated: 0, errors: [ { row: 0, message: t("org_structure.import.no_file") } ])
      return render :import, status: :unprocessable_entity
    end

    @result = OrgUnitImportService.import(file: file, company: company)
    if @result.success?
      log_action("IMPORT_ORG_UNITS")
      redirect_to dashboard_org_units_path,
        notice: t("org_structure.import.done", created: @result.created, updated: @result.updated),
        status: :see_other
    else
      render :import, status: :unprocessable_entity
    end
  end

  def template
    send_data OrgUnitImportService.template_csv,
      filename: "org_units_template.csv", type: "text/csv"
  end

  private

  def company
    @company ||= current_company
  end

  def company_scope
    company.org_units
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("org_structure.flash.no_company"), status: :see_other
  end

  def can_manage_org_structure?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_org_structure?

    redirect_to dashboard_org_units_path, alert: t("org_structure.flash.no_permission"), status: :see_other
  end

  def set_org_unit
    @org_unit = company_scope.find_by(id: params[:id])
    return if @org_unit

    redirect_to dashboard_org_units_path, alert: t("org_structure.flash.not_found"), status: :see_other
  end

  def default_level_for(parent_id)
    parent = company_scope.find_by(id: parent_id)
    return 1 if parent.nil?

    [ parent.level + 1, OrgLevelDefinition::MAX_LEVEL ].min
  end

  def suggested_code(parent_id)
    parent = company_scope.find_by(id: parent_id)
    HierarchicalCodeService.next_org_unit_code(company: company, parent: parent)
  end

  # The drawer form needs the tree context whether it is rendered fresh or
  # re-rendered with validation errors.
  def render_drawer(status: :ok)
    @level_definitions = company.org_level_definitions.ordered.to_a
    @groups = company.org_groups.ordered.to_a
    @parent_options = company_scope.active.ordered.to_a
    @parent_options -= [ @org_unit ] if @org_unit&.persisted?
    render(@org_unit&.persisted? ? :edit : :new, status: status)
  end

  def org_unit_params
    permitted = params.require(:org_unit).permit(
      :parent_id, :org_group_id, :level, :code, :name_en, :name_ar,
      :head_user_id, :cost_center, :email, :sort_order, :active, mandates: []
    )
    mandates = permitted.delete(:mandates)
    permitted.tap do |attrs|
      attrs[:mandates] = Array(mandates).map { |m| m.to_s.strip }.reject(&:blank?) unless mandates.nil?
    end
  end

  def log_action(action)
    AuditLogService.log_action(
      actor_user: current_user,
      company: company,
      action: action,
      entity_type: "org_unit",
      entity_id: @org_unit&.id,
      payload: { code: @org_unit&.code, name: @org_unit&.display_name }
    )
  rescue => e
    Rails.logger.warn "OrgUnits audit log failed: #{e.class}: #{e.message}"
  end
end
