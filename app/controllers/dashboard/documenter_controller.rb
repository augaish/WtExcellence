class Dashboard::DocumenterController < Dashboard::BaseController
  requires_module :pp
  before_action :authenticate_user!
  before_action :ensure_company_present
  before_action :ensure_can_manage, only: [
    :settings, :update_settings, :create_holiday, :destroy_holiday,
    :add_assignee, :remove_assignee
  ]

  helper_method :can_manage_documenter?, :can_return_records?, :stage_target_for, :working_days_for

  # One screen per lifecycle phase; a section per stage within it.
  def index
    @phase = params[:phase].presence
    @phase = PpStage::PHASES.first unless PpStage::PHASES.include?(@phase)

    records = company.pp_records.active
      .includes(:owner_org_unit, :owner_user, :package, :stage_assignees, :stage_approvals)
      .to_a

    @by_stage = records.group_by(&:stage_key)
    @counts_by_phase = PpStage::PHASES.index_with do |phase|
      PpStage.in_phase(phase).sum { |d| (@by_stage[d[:key]] || []).size }
    end
    @stages = PpStage.in_phase(@phase)
    @org_units = company.org_units.active.ordered.to_a
    @company_users = company.users.order(:name).to_a
  end

  # "Move selected forward" — every record validated independently server-side.
  def advance
    records = company.pp_records.where(id: Array(params[:record_ids]).reject(&:blank?)).to_a

    if records.empty?
      return redirect_back_to_worklist(alert: t("documenter.flash.nothing_selected"))
    end

    result = PpStageTransitionService.advance_many(records: records, user: current_user, company: company)

    if result.success?
      redirect_back_to_worklist(notice: t("documenter.flash.advanced", count: result.moved.size))
    else
      detail = result.errors.first(3).map { |e| "#{e[:record].display_title}: #{e[:message]}" }.join(" · ")
      redirect_back_to_worklist(
        alert: t("documenter.flash.advanced_partial", moved: result.moved.size, skipped: result.skipped.size, detail: detail)
      )
    end
  end

  # Return a record to an earlier stage. Gated separately and always with a reason.
  def return_to
    record = company.pp_records.find_by(id: params[:record_id])
    return redirect_back_to_worklist(alert: t("pp_records.flash.not_found")) unless record

    PpStageTransitionService.return_to(
      record: record, user: current_user, company: company,
      stage_key: params[:stage_key], reason: params[:reason]
    )
    redirect_back_to_worklist(notice: t("documenter.flash.returned", title: record.display_title))
  rescue PpStageTransitionService::TransitionError => e
    redirect_back_to_worklist(alert: e.message)
  end

  # The branch answer captured at s2_confirmation.
  def update_intersections
    record = find_record or return
    has = ActiveModel::Type::Boolean.new.cast(params[:has_intersections])
    record.update!(has_intersections: has)

    # Pre-seed the stakeholder chain from the units the user named.
    if has
      Array(params[:org_unit_ids]).reject(&:blank?).each do |unit_id|
        unit = company.org_units.find_by(id: unit_id)
        next if unit.nil?

        record.stage_approvals.find_or_create_by!(stage_key: "s2_stakeholders", org_unit: unit) do |a|
          a.requested_at = Time.current
          a.requested_by = current_user
        end
      end
    end

    redirect_back_to_worklist(notice: t("documenter.flash.intersections_saved"))
  end

  # ---- Approval chains ---------------------------------------------------

  def add_approval
    record = find_record or return
    unit = company.org_units.find_by(id: params[:org_unit_id])
    return redirect_back_to_worklist(alert: t("documenter.flash.unit_not_found")) unless unit

    stage_key = params[:stage_key].presence || record.stage_key
    unless PpStage.approval_stage?(stage_key)
      return redirect_back_to_worklist(alert: t("documenter.flash.not_an_approval_stage"))
    end

    record.stage_approvals.find_or_create_by!(stage_key: stage_key, org_unit: unit) do |a|
      # requested_at is stamped now — the clock for this unit starts here.
      a.requested_at = Time.current
      a.requested_by = current_user
    end

    redirect_back_to_worklist(notice: t("documenter.flash.approval_requested", unit: unit.display_name))
  end

  def receive_approval
    approval = find_approval or return

    approval.update!(received_at: Time.current, received_by: current_user)
    redirect_back_to_worklist(notice: t("documenter.flash.approval_received", unit: approval.org_unit.display_name))
  end

  def remove_approval
    approval = find_approval or return

    unit_name = approval.org_unit.display_name
    approval.destroy
    redirect_back_to_worklist(notice: t("documenter.flash.approval_removed", unit: unit_name))
  end

  # ---- Stage assignees ---------------------------------------------------

  def add_assignee
    record = find_record or return
    user = company.users.find_by(id: params[:user_id])
    return redirect_back_to_worklist(alert: t("documenter.flash.user_not_found")) unless user

    stage_key = params[:stage_key].presence || record.stage_key
    record.stage_assignees.find_or_create_by!(stage_key: stage_key, user: user)
    redirect_back_to_worklist(notice: t("documenter.flash.assignee_added", name: user.name))
  end

  def remove_assignee
    record = find_record or return

    record.stage_assignees.find_by(id: params[:assignee_id])&.destroy
    redirect_back_to_worklist(notice: t("documenter.flash.assignee_removed"))
  end

  # ---- Reopen as a new version -------------------------------------------

  # A closed record is never rewound. Reopening creates v(n+1) that starts the
  # lifecycle again, while the published version stays exactly as it was.
  def reopen
    record = find_record or return

    unless record.terminal_stage?
      return redirect_back_to_worklist(alert: t("documenter.flash.only_closed_reopen"))
    end

    new_version = nil
    ActiveRecord::Base.transaction do
      new_version = company.pp_records.create!(
        record_type: record.record_type,
        code: "#{record.code}-v#{record.version_number + 1}",
        title_en: record.title_en, title_ar: record.title_ar,
        description: record.description,
        version_label: next_version_label(record),
        owner_user_id: record.owner_user_id,
        owner_org_unit_id: record.owner_org_unit_id,
        pp_process_id: record.pp_process_id,
        current_stage: PpStage::FIRST_KEY,
        stage_entered_at: Time.current,
        version_number: record.version_number + 1,
        previous_version: record
      )
    end

    AuditLogService.log_action(
      actor_user: current_user, company: company, action: "PP_RECORD_REOPENED",
      entity_type: "pp_record", entity_id: new_version.id,
      payload: { from: record.id, version: new_version.version_number }
    )

    redirect_to dashboard_pp_record_path(new_version),
      notice: t("documenter.flash.reopened", version: new_version.version_number), status: :see_other
  end

  # ---- Settings ----------------------------------------------------------

  def settings
    @targets = PpStage::KEYS.index_with { |key| stage_target_for(key) }
    @holidays = company.company_holidays.ordered.to_a
    @weekend_days = WorkingDaysService.new(company).weekend_days
  end

  def update_settings
    submitted = params.fetch(:targets, {}).permit!.to_h

    ActiveRecord::Base.transaction do
      submitted.each do |stage_key, value|
        next unless PpStage.exists?(stage_key)

        target = company.pp_stage_targets.find_or_initialize_by(stage_key: stage_key)
        target.target_days = value.to_i
        target.save!
      end

      if params[:weekend_days].present?
        days = Array(params[:weekend_days]).reject(&:blank?).map(&:to_i).select { |d| d.between?(0, 6) }
        company.update!(weekend_days: days)
      end
    end

    redirect_to dashboard_documenter_settings_path, notice: t("documenter.flash.settings_saved"), status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to dashboard_documenter_settings_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def create_holiday
    holiday = company.company_holidays.new(
      name: params[:name], start_date: params[:start_date], end_date: params[:end_date]
    )

    if holiday.save
      redirect_to dashboard_documenter_settings_path, notice: t("documenter.flash.holiday_added"), status: :see_other
    else
      redirect_to dashboard_documenter_settings_path, alert: holiday.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy_holiday
    company.company_holidays.find_by(id: params[:holiday_id])&.destroy
    redirect_to dashboard_documenter_settings_path, notice: t("documenter.flash.holiday_removed"), status: :see_other
  end

  private

  def company
    @company ||= current_company
  end

  def ensure_company_present
    return if company

    redirect_to dashboard_overview_path, alert: t("pp_records.flash.no_company"), status: :see_other
  end

  def can_manage_documenter?
    return true if current_user&.platform_admin?

    cu = current_user&.company_user
    cu.present? && (cu.has_admin_privileges? || cu.company_quality_manager?)
  end
  alias can_return_records? can_manage_documenter?

  def ensure_can_manage
    return if can_manage_documenter?

    redirect_to dashboard_documenter_path, alert: t("documenter.flash.no_permission"), status: :see_other
  end

  def find_record
    record = company.pp_records.find_by(id: params[:id])
    return record if record

    redirect_back_to_worklist(alert: t("pp_records.flash.not_found"))
    nil
  end

  def find_approval
    approval = PpStageApproval.joins(:pp_record)
      .where(pp_records: { company_id: company.id })
      .find_by(id: params[:approval_id])
    return approval if approval

    redirect_back_to_worklist(alert: t("documenter.flash.approval_not_found"))
    nil
  end

  def stage_target_for(stage_key)
    PpStageTarget.days_for(company, stage_key)
  end

  def working_days_for(record)
    record.working_days_in_stage
  end

  def next_version_label(record)
    current = record.version_label.to_s[/\d+/]
    current ? "v#{current.to_i + 1}.0" : "v#{record.version_number + 1}.0"
  end

  def redirect_back_to_worklist(**flash_opts)
    redirect_to dashboard_documenter_path(phase: params[:phase]), status: :see_other, **flash_opts
  end
end
