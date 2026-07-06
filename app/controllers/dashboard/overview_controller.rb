class Dashboard::OverviewController < Dashboard::BaseController
  before_action :require_overview_access

  def index
    t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timings = {}
    mark = ->(label) {
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      timings[label] = ((now - t_start) * 1000).round(1)
      t_start = now
    }

    # Date range handling (default to last 7 days)
    @date_from = params[:date_from].present? ? Date.parse(params[:date_from]) : 7.days.ago.to_date
    @date_to = params[:date_to].present? ? Date.parse(params[:date_to]) : Date.today

    # Format date range text: "01-07 Oct, 2025"
    if @date_from.month == @date_to.month && @date_from.year == @date_to.year
      @date_range_text = "#{@date_from.strftime('%d')}-#{@date_to.strftime('%d')} #{@date_to.strftime('%b')}, #{@date_to.strftime('%Y')}"
    else
      @date_range_text = "#{@date_from.strftime('%d %b')} - #{@date_to.strftime('%d %b')}, #{@date_to.strftime('%Y')}"
    end

    # Determine if we should filter by company (non–platform-admins see only their company)
    @filter_by_company = !current_user&.platform_admin?
    @company_id = current_company&.id if @filter_by_company

    # Show Total Active Standards and Total Users only to super admin, company admin, quality manager
    @show_admin_metrics = overview_show_admin_metrics?

    # Period bounds for all metrics (every metric is based on this date range)
    period_start = @date_from.beginning_of_day
    period_end = @date_to.end_of_day

    mark.call(:setup)

    # TOP METRICS ROW
    # Total Active Standards (as of period end) and added in period — only for admin/QM
    if @show_admin_metrics
      active_standards_scope = CompanyStandard.active
      active_standards_scope = active_standards_scope.where(company_id: @company_id) if @filter_by_company
      @total_active_standards = active_standards_scope.count
      @active_standards_added_in_period = active_standards_scope
        .where("created_at >= ? AND created_at <= ?", period_start, period_end)
        .count
    else
      @total_active_standards = nil
      @active_standards_added_in_period = nil
    end

    # Total Companies (only for super admins)
    @total_companies = Company.active.count unless @filter_by_company

    # Total Users (for company admin and quality manager only; contributor/auditor/viewer do not see)
    @total_users = if @filter_by_company && @show_admin_metrics
      current_company.company_users.count
    else
      nil
    end

    # Compliance-table rows: only cheap data (name + total_versions). The
    # compliance % per standard is loaded asynchronously by the client so
    # initial render stays fast.
    standards_scope = Standard.joins(:company_standards)
                             .where(company_standards: { status: "active" })
    standards_scope = standards_scope.where(company_standards: { company_id: @company_id }) if @filter_by_company

    @standards_compliance = standards_scope.distinct.limit(10).map do |standard|
      {
        standard: standard,
        total_versions: standard.standard_versions.count
      }
    end

    mark.call(:compliance_table_rows)

    # Credits/Tokens Used - scoped to period
    @credits_data = calculate_credits_data(period_start, period_end)

    mark.call(:credits_data)

    # SECOND METRICS ROW - all CAPA counts scoped to created_at in period (role-scoped for company users)
    capas_scope = if @filter_by_company && @company_id
      capa_visible_scope(base: Capa.where(company_id: @company_id).not_archived)
    else
      Capa.not_archived
    end
    capas_in_period_scope = capas_scope.where("capas.created_at >= ? AND capas.created_at <= ?", period_start, period_end)

    @total_capas = capas_in_period_scope.count
    @capas_created_in_period = @total_capas

    @open_capas = capas_in_period_scope.where(status: "open").count
    @open_capas_in_period = @open_capas

    @high_priority_capas = capas_in_period_scope.where(priority: "high").count

    # Overdue CAPAs: overdue as of period end date
    @overdue_capas = capas_scope
      .where("capas.due_date < ?", @date_to)
      .where.not(capas: { status: :closed })
      .where.not(capas: { due_date: nil })
      .count

    # CHARTS DATA - full date range
    all_dates = (@date_from..@date_to).map { |d| d.strftime("%b %d") }

    total_by_date_scope = capas_scope.where("capas.created_at >= ? AND capas.created_at <= ?", period_start, period_end)
    total_by_date = total_by_date_scope
      .group(Arel.sql("DATE(capas.created_at)"))
      .count
      .transform_keys { |date| date.is_a?(Date) ? date.strftime("%b %d") : Date.parse(date.to_s).strftime("%b %d") }

    closed_by_date_scope = capas_scope
      .where("capas.created_at >= ? AND capas.created_at <= ?", period_start, period_end)
      .where(capas: { status: "closed" })
    closed_by_date = closed_by_date_scope
      .group(Arel.sql("DATE(capas.created_at)"))
      .count
      .transform_keys { |date| date.is_a?(Date) ? date.strftime("%b %d") : Date.parse(date.to_s).strftime("%b %d") }

    closed_data = all_dates.map { |date_label| [ date_label, closed_by_date[date_label] || 0 ] }.to_h
    total_data = all_dates.map { |date_label| [ date_label, total_by_date[date_label] || 0 ] }.to_h

    @capa_over_time = [
      { name: "Closed CAPA", data: closed_data },
      { name: "Total CAPA", data: total_data }
    ]

    # CAPAs by Status Breakdown - CAPAs created in period
    @status_breakdown = capas_in_period_scope.group("capas.status").count
    @status_breakdown.default = 0

    mark.call(:capa_metrics_and_charts)

    # GOVERNANCE METRICS (Risk / Vendor / Customer Commitment).
    # Platform admins see a cross-company rollup; everyone else is company-scoped.
    load_governance_metrics(@filter_by_company ? @company_id : nil)
    mark.call(:governance_metrics)

    # Customizable layout (which widgets show, in what order) — admins can edit,
    # everyone in the scope renders the active layout.
    load_dashboard_layout
    mark.call(:dashboard_layout)

    # AI Usage Overview (credits over time) - full period
    @tokens_over_time = calculate_credits_over_time(@date_from, @date_to)

    mark.call(:credits_over_time)

    # Overdue CAPA table - overdue as of period end date (role-scoped for company users)
    overdue_scope = if @filter_by_company && @company_id
      capa_visible_scope(base: Capa.where(company_id: @company_id).not_archived
        .where("capas.due_date < ?", @date_to)
        .where.not(capas: { status: :closed })
        .where.not(capas: { due_date: nil }))
    else
      overdue_scope = Capa.not_archived
        .where("due_date < ?", @date_to)
        .where.not(status: :closed)
        .where.not(due_date: nil)
      overdue_scope = overdue_scope.where(company_id: @company_id) if @filter_by_company
      overdue_scope
    end

    @overdue_capas_list = overdue_scope
                               .includes(:standard, :company_users, :users)
                               .order("capas.due_date ASC, capas.created_at DESC")
                               .limit(10)

    mark.call(:overdue_list)

    Rails.logger.warn("[overview-timings] #{timings.inspect} total=#{timings.values.sum.round(1)}ms")
  end

  # JSON-only endpoint — returns per-standard compliance for the top 10 standards
  # shown in the overview table. Keyed by standard id so the client can swap each
  # row's spinner for the real number.
  def standards_compliance
    filter_by_company = !current_user&.platform_admin?
    company_id = filter_by_company ? current_company&.id : nil

    scope = Standard.joins(:company_standards).where(company_standards: { status: "active" })
    scope = scope.where(company_standards: { company_id: company_id }) if filter_by_company
    standards = scope.distinct.limit(10).to_a

    compliance_by_id = standards.each_with_object({}) do |standard, acc|
      acc[standard.id] = per_standard_compliance(standard, filter_by_company: filter_by_company).to_f.round(2)
    end

    render json: { compliance: compliance_by_id }
  end

  # JSON-only endpoint — reads the average compliance across ALL active standards
  # from the `company_standards.cached_compliance_percentage` cache.
  def avg_compliance
    filter_by_company = !current_user&.platform_admin?
    company_id = filter_by_company ? current_company&.id : nil

    scope = CompanyStandard.active
    scope = scope.where(company_id: company_id) if filter_by_company

    # Populate any nil caches lazily, then average across the resulting set.
    scope.where(cached_compliance_percentage: nil).each(&:refresh_compliance_cache!)

    if filter_by_company
      avg = scope.average(:cached_compliance_percentage).to_f.round(2)
    else
      # Super-admin: first average per (standard), then average across standards
      # so standards with many companies don't dominate.
      per_standard = scope.group(:standard_id).average(:cached_compliance_percentage)
      avg = per_standard.any? ? (per_standard.values.sum(&:to_f) / per_standard.size).round(2) : 0
    end

    render json: { avg_compliance: avg }
  end

  private

  # Load the active customizable layout for the current scope (platform for
  # platform admins, otherwise the company's shared layout). Exposes the active
  # layout for rendering, all three slots for the switcher, and whether the
  # current user may customize.
  def load_dashboard_layout
    scope = current_user&.platform_admin? ? "platform" : "company"
    company_id = scope == "platform" ? nil : current_company&.id

    @dashboard_scope = scope
    @can_customize = current_user&.platform_admin? || current_user&.company_user&.company_admin? || false
    @active_slot = DashboardLayout.active_slot(scope: scope, company_id: company_id)
    @dashboard_layout = DashboardLayout.resolve(scope: scope, company_id: company_id, slot: @active_slot)
    @layout_slots = DashboardLayout::SLOTS.map do |slot|
      layout = DashboardLayout.resolve(scope: scope, company_id: company_id, slot: slot)
      { slot: slot, name: layout.name.presence || "#{t('layout', default: 'Layout')} #{slot}", active: slot == @active_slot }
    end
  end

  # Governance (Risk / Vendor / Customer Commitment) metrics for the overview.
  # Pass a company_id to scope to one company; pass nil for a platform-wide
  # rollup across every company (super admin view).
  def load_governance_metrics(company_id)
    risks = Risk.active
    risks = risks.where(company_id: company_id) if company_id
    @risk_total = risks.count
    @risk_open = risks.where.not(status: "closed").count
    level_counts = Hash.new(0)
    matrix = Hash.new(0)
    risks.select(:likelihood, :impact, :inherent_score).each do |r|
      level_counts[r.inherent_level] += 1
      matrix[[ r.likelihood, r.impact ]] += 1
    end
    @risk_by_level = level_counts
    @risk_matrix = matrix

    vendors = Vendor.active
    vendors = vendors.where(company_id: company_id) if company_id
    @vendor_total = vendors.count
    @vendor_by_level = vendors.group(:risk_level).count
    @vendor_high = vendors.where(risk_level: %w[high critical]).count

    commitments = CustomerCommitment.active
    commitments = commitments.where(company_id: company_id) if company_id
    @commitment_total = commitments.count
    @commitment_overdue = commitments.select(&:past_due?).size
    @commitment_due_soon = commitments.due_soon.count
  end

  # Compute one standard's compliance, routing by role. Shared by `index` (top 10)
  # and `avg_compliance` (all). Uses the (standard, company) cache when possible.
  def per_standard_compliance(standard, filter_by_company: @filter_by_company)
    if filter_by_company
      cs = CompanyStandard.find_by(standard_id: standard.id, company_id: current_company&.id)
      cs ? cs.compliance_percentage : 0
    else
      scope = CompanyStandard.active.where(standard_id: standard.id)
      scope.where(cached_compliance_percentage: nil).each(&:refresh_compliance_cache!)
      scope.average(:cached_compliance_percentage).to_f.round(2)
    end
  end


  def require_overview_access
    return if current_user&.platform_admin?
    return if current_user&.company_user.present?

    redirect_to dashboard_path, alert: "You do not have access to this page.", status: :see_other
  end

  # Total Active Standards and Total Users are shown only to platform admins, company admin, quality manager
  def overview_show_admin_metrics?
    return true if current_user&.platform_admin?
    cu = current_user&.company_user
    cu&.company_admin? || cu&.company_quality_manager?
  end

  # Calculate compliance for a single company
  def calculate_company_compliance(standard, standard_version, company)
    return 0 unless standard_version
    return 0 unless company.present?

    result = ClauseScoreCalculator.calculate_compliance_for_company(standard, company)
    result ? result[:compliance_percentage].to_f : 0
  end

  # Calculate average compliance across all companies (for super admins)
  def calculate_average_compliance_across_companies(standard, standard_version)
    return 0 unless standard_version

    assigned_companies = standard.company_standards
                                 .where(status: "active")
                                 .includes(:company)
                                 .map(&:company)

    return 0 if assigned_companies.empty?

    total = 0.0
    assigned_companies.each do |company|
      r = ClauseScoreCalculator.calculate_compliance_for_company(standard, company)
      total += r ? r[:compliance_percentage].to_f : 0
    end

    (total / assigned_companies.count).round(2)
  end

  # Calculate credits data (used and used_in_period, both scoped to period)
  def calculate_credits_data(period_start, period_end)
    if @filter_by_company
      company_user = current_user&.company_user
      credits_limit = company_user&.assigned_credits || 0

      ai_activities = get_ai_activities_for_company(current_company.id)
      activities_in_period = ai_activities.where("created_at >= ? AND created_at <= ?", period_start, period_end)
      credits_used_in_period = calculate_total_credits_from_logs(activities_in_period)

      {
        used: credits_used_in_period,
        limit: credits_limit,
        used_in_period: credits_used_in_period
      }
    else
      ai_activities = get_ai_activities_for_all_companies
      activities_in_period = ai_activities.where("created_at >= ? AND created_at <= ?", period_start, period_end)
      credits_used_in_period = calculate_total_credits_from_logs(activities_in_period)

      {
        used: credits_used_in_period,
        limit: nil,
        used_in_period: credits_used_in_period
      }
    end
  end

  # Get AI activities for a specific company
  def get_ai_activities_for_company(company_id)
    ai_actions = [ "GENERATE_CAPA_ACTIONS", "GENERATE_CAPA_QUESTIONNAIRE", "SUGGEST_CAPA_CLAUSES" ]

    root_cause_regeneration = AuditLog.where(company_id: company_id)
                                      .where(action: "UPDATE_CAPA_QUESTIONNAIRE")
                                      .where("payload_json->>'step' = ?", "regenerate_root_cause")

    AuditLog.where(company_id: company_id)
            .where(action: ai_actions)
            .or(root_cause_regeneration)
  end

  # Get AI activities for all companies (super admin)
  def get_ai_activities_for_all_companies
    ai_actions = [ "GENERATE_CAPA_ACTIONS", "GENERATE_CAPA_QUESTIONNAIRE", "SUGGEST_CAPA_CLAUSES" ]

    root_cause_regeneration = AuditLog.where(action: "UPDATE_CAPA_QUESTIONNAIRE")
                                      .where("payload_json->>'step' = ?", "regenerate_root_cause")

    AuditLog.where(action: ai_actions)
            .or(root_cause_regeneration)
  end

  # Calculate total credits from audit logs
  def calculate_total_credits_from_logs(audit_logs)
    total = 0
    audit_logs.each do |log|
      credits_used = log.payload_json&.dig("credits_used") || get_credits_for_action(log)
      total += credits_used
    end
    total
  end

  # Get credits for an action (fallback if not in payload)
  def get_credits_for_action(log)
    if log.action == "UPDATE_CAPA_QUESTIONNAIRE" && log.payload_json&.dig("step") == "regenerate_root_cause"
      return 0
    end

    action_key = log.action == "UPDATE_CAPA_QUESTIONNAIRE" && log.payload_json&.dig("step") == "regenerate_root_cause" ? "REGENERATE_ROOT_CAUSE" : log.action
    CreditService.get_cost(action_key)
  end

  # Calculate credits over time for chart (scoped to period)
  def calculate_credits_over_time(start_date, end_date)
    all_dates = (start_date.to_date..end_date.to_date).map { |d| d.strftime("%b %d") }
    period_end = end_date.to_date.end_of_day

    if @filter_by_company
      ai_activities = get_ai_activities_for_company(current_company.id)
        .where("created_at >= ? AND created_at <= ?", start_date, period_end)
        .to_a
    else
      ai_activities = get_ai_activities_for_all_companies
        .where("created_at >= ? AND created_at <= ?", start_date, period_end)
        .to_a
    end

    # Group by date and sum credits
    credits_by_date = Hash.new(0)
    ai_activities.each do |log|
      date_key = log.created_at.to_date.strftime("%b %d")
      credits_used = log.payload_json&.dig("credits_used") || get_credits_for_action(log)
      credits_by_date[date_key] += credits_used.to_i
    end

    # Ensure all dates are present with at least 0
    result = {}
    all_dates.each do |date_label|
      result[date_label] = (credits_by_date[date_label] || 0).to_i
    end
    result
  end
end
