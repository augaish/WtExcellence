class Dashboard::PpDiagramsController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, except: [ :show ]
  before_action :set_diagram, only: [
    :show, :edit, :update, :destroy,
    :add_element, :update_element, :destroy_element, :add_flow, :destroy_flow
  ]

  helper_method :can_manage_diagrams?

  def show
    load_editor_data
  end

  def new
    @owner = find_owner
    return redirect_to dashboard_pp_records_path, alert: t("architect.flash.owner_not_found"), status: :see_other unless @owner

    @diagram = company.pp_diagrams.new(owner: @owner, name: default_name(@owner))
  end

  def create
    owner = find_owner
    return redirect_to dashboard_pp_records_path, alert: t("architect.flash.owner_not_found"), status: :see_other unless owner

    @diagram = company.pp_diagrams.new(diagram_params)
    @diagram.company = company
    @diagram.owner = owner

    if @diagram.save
      log_action("CREATE_DIAGRAM")
      redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.created"), status: :see_other
    else
      @owner = owner
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @diagram.update(diagram_params)
      log_action("UPDATE_DIAGRAM")
      redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.updated"), status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    owner = @diagram.owner
    @diagram.destroy
    log_action("DELETE_DIAGRAM")
    redirect_to owner_path(owner), notice: t("architect.flash.deleted"), status: :see_other
  end

  # ---- Elements ----------------------------------------------------------

  def add_element
    element = @diagram.elements.new(element_params)
    element.position = (@diagram.elements.maximum(:position) || -1) + 1

    if element.save
      redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.element_added"), status: :see_other
    else
      redirect_to dashboard_pp_diagram_path(@diagram), alert: element.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update_element
    element = @diagram.elements.find_by(id: params[:element_id])
    return redirect_to dashboard_pp_diagram_path(@diagram), alert: t("architect.flash.element_not_found"), status: :see_other unless element

    if element.update(element_params)
      redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.element_updated"), status: :see_other
    else
      redirect_to dashboard_pp_diagram_path(@diagram), alert: element.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy_element
    @diagram.elements.find_by(id: params[:element_id])&.destroy
    redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.element_removed"), status: :see_other
  end

  # ---- Flows -------------------------------------------------------------

  def add_flow
    flow = @diagram.flows.new(
      from_element_id: params[:from_element_id],
      to_element_id: params[:to_element_id],
      kind: params[:kind].presence || "sequence",
      label: params[:label]
    )

    if flow.save
      redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.flow_added"), status: :see_other
    else
      redirect_to dashboard_pp_diagram_path(@diagram), alert: flow.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy_flow
    @diagram.flows.find_by(id: params[:flow_id])&.destroy
    redirect_to dashboard_pp_diagram_path(@diagram), notice: t("architect.flash.flow_removed"), status: :see_other
  end

  private

  def company
    @company ||= current_company
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("pp_records.flash.no_company"), status: :see_other
  end

  def can_manage_diagrams?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end

  def ensure_can_manage
    return if can_manage_diagrams?

    redirect_to dashboard_pp_records_path, alert: t("architect.flash.no_permission"), status: :see_other
  end

  def set_diagram
    @diagram = company.pp_diagrams.includes(:elements, :flows).find_by(id: params[:id])
    return if @diagram

    redirect_to dashboard_pp_records_path, alert: t("architect.flash.not_found"), status: :see_other
  end

  def load_editor_data
    @elements = @diagram.elements.to_a
    @flows = @diagram.flows.includes(:from_element, :to_element).to_a
    @svg = ProcessDiagramRenderer.render(@diagram)
  end

  # A diagram is always opened FROM a record or a process.
  def find_owner
    case params[:owner_type]
    when "PpRecord" then company.pp_records.find_by(id: params[:owner_id])
    when "PpProcess" then company.pp_processes.find_by(id: params[:owner_id])
    end
  end

  def owner_path(owner)
    owner.is_a?(PpProcess) ? dashboard_pp_processes_path : dashboard_pp_record_path(owner)
  end
  helper_method :owner_path

  def default_name(owner)
    title = owner.respond_to?(:display_title) ? owner.display_title : owner.display_name
    t("architect.default_name", title: title)
  end

  def diagram_params
    params.require(:pp_diagram).permit(:name, :trigger_text, :inputs_summary, :outputs_summary)
  end

  def element_params
    params.require(:pp_diagram_element).permit(
      :element_type, :title, :performer, :description, :input, :output,
      :trigger_text, :scope, :flow_label, :position
    )
  end

  def log_action(action)
    AuditLogService.log_action(
      actor_user: current_user, company: company, action: action,
      entity_type: "pp_diagram", entity_id: @diagram&.id,
      payload: { name: @diagram&.name }
    )
  end
end
