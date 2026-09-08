class Dashboard::AiInsightsController < Dashboard::BaseController
  before_action :require_company_user
  before_action :prevent_contributor_access
  before_action :require_company_admin_for_admin_tabs, only: [:show]

  def show
    allowed_tabs = ["my_overview", "my_credits"]
    allowed_tabs += ["overview", "credits", "credit_assignments"] if current_user&.company_user&.company_admin?

    @tab = params[:tab]

    unless allowed_tabs.include?(@tab)
      @tab = current_user&.company_user&.company_admin? ? "overview" : "my_overview"
    end
    
    if current_company
      @current_credits = current_company.credits || 1000
      if @tab == "credit_assignments"
        require_company_admin
        @company_users = current_company.company_users.includes(:user).references(:user).order("users.name ASC")
        @company_credit_pool = current_company.credits || 0
        @company_assigned_credits = @company_users.sum(:assigned_credits).to_i
        @company_total_credits = @company_credit_pool.to_i + @company_assigned_credits
      end
      
      # Get AI-related audit logs (including root cause regeneration)
      @ai_activities = get_ai_activities
                               .includes(:actor_user)
                               .order(created_at: :desc)
                               .limit(50)

      my_ai_activities_scope = get_ai_activities.where(actor_user_id: current_user.id)
      @my_ai_activities = my_ai_activities_scope
                                           .includes(:actor_user)
                                           .order(created_at: :desc)
                                           .limit(50)
      
      # Calculate usage statistics
      @total_ai_actions = @ai_activities.count
      @total_credits_used = calculate_total_credits_used
      @usage_by_action = calculate_usage_by_action
      @usage_over_time = calculate_usage_over_time
      @most_used_feature = find_most_used_feature
      @top_credit_spenders = calculate_top_credit_spenders
      @most_used_activities = calculate_most_used_activities

      @my_total_ai_actions = my_ai_activities_scope.count
      @my_total_credits_used = calculate_total_credits_used(my_ai_activities_scope)
      @my_usage_over_time = calculate_usage_over_time(my_ai_activities_scope)
      @my_usage_by_action = calculate_usage_by_action(my_ai_activities_scope)
      @my_most_used_feature = find_most_used_feature(@my_usage_by_action)
      @my_most_used_activities = calculate_most_used_activities(my_ai_activities_scope)
      @credit_usage_chart = calculate_credit_usage_over_time
      @my_credit_usage_chart = calculate_credit_usage_over_time(my_ai_activities_scope)
      @my_credit_balance = current_user.company_user&.credit_balance || 0
      @my_top_credit_cost_activities = calculate_top_credit_cost_activities(my_ai_activities_scope)
    else
      @current_credits = 0
      @ai_activities = []
      @total_ai_actions = 0
      @total_credits_used = 0
      @usage_by_action = {}
      @usage_over_time = []
      @most_used_feature = nil
      @top_credit_spenders = []
      @most_used_activities = []
      @company_users = []
      @company_credit_pool = 0
      @company_assigned_credits = 0
      @company_total_credits = 0
      @my_ai_activities = []
      @my_total_ai_actions = 0
      @my_total_credits_used = 0
      @my_usage_over_time = []
      @my_usage_by_action = {}
      @my_most_used_feature = nil
      @my_most_used_activities = []
      @credit_usage_chart = {}
      @my_credit_usage_chart = {}
      @my_credit_balance = 0
      @my_top_credit_cost_activities = []
    end
  end

  private

  def calculate_total_credits_used(audit_logs = get_ai_activities)
    return 0 unless current_company

    total = 0
    audit_logs.each do |log|
      credits_used = log.payload_json&.dig("credits_used") || get_credits_for_action(log)
      total += credits_used
    end
    
    total
  end

  def calculate_usage_by_action(audit_logs = get_ai_activities)
    return {} unless current_company

    usage = {}
    
    audit_logs.each do |log|
      action_key = get_action_key_for_statistics(log)
      usage[action_key] ||= 0
      usage[action_key] += 1
    end
    
    usage
  end

  def calculate_usage_over_time(audit_logs = get_ai_activities)
    return [] unless current_company

    thirty_days_ago = 30.days.ago.beginning_of_day
    
    # Get usage per day for last 30 days
    usage_by_date = audit_logs
                            .where("created_at >= ?", thirty_days_ago)
                            .group(Arel.sql("DATE(created_at)"))
                            .count
                            .transform_keys { |date| date.is_a?(Date) ? date.strftime("%b %d") : Date.parse(date.to_s).strftime("%b %d") }
    
    # Fill in all dates for the last 30 days
    all_dates = (30.days.ago.to_date..Date.today).map { |d| d.strftime("%b %d") }
    all_dates.map { |date| [date, usage_by_date[date] || 0] }.to_h
  end

  def find_most_used_feature(usage_by_action = @usage_by_action)
    return nil if usage_by_action.empty?
    
    usage_by_action.max_by { |_action, count| count }&.first
  end

  def calculate_credit_usage_over_time(audit_logs = get_ai_activities)
    return {} unless current_company

    thirty_days_ago = 30.days.ago.beginning_of_day
    usage_by_date = Hash.new(0)

    scoped_logs = audit_logs.where("created_at >= ?", thirty_days_ago)
    scoped_logs.each do |log|
      date_key = log.created_at.to_date.strftime("%b %d")
      credits_used = log.payload_json&.dig("credits_used")
      credits_used = get_credits_for_action(log) if credits_used.nil?
      usage_by_date[date_key] += credits_used
    end

    all_dates = (30.days.ago.to_date..Date.today).map { |d| d.strftime("%b %d") }
    all_dates.map { |date| [date, usage_by_date[date] || 0] }.to_h
  end

  def calculate_top_credit_spenders
    return [] unless current_company

    audit_logs = get_ai_activities
                         .includes(:actor_user)
    
    # Group by user and calculate total credits spent
    user_credits = {}
    audit_logs.each do |log|
      next unless log.actor_user
      
      user_id = log.actor_user.id
      credits_used = log.payload_json&.dig("credits_used") || get_credits_for_action(log)
      
      user_credits[user_id] ||= { user: log.actor_user, total_credits: 0, action_count: 0 }
      user_credits[user_id][:total_credits] += credits_used
      user_credits[user_id][:action_count] += 1
    end
    
    # Sort by total credits (descending) and return top 10
    user_credits.values.sort_by { |data| -data[:total_credits] }.first(10)
  end

  def calculate_most_used_activities(audit_logs = get_ai_activities)
    return [] unless current_company
    
    # Group by action and calculate count and total cost
    activity_stats = {}
    audit_logs.each do |log|
      action_key = get_action_key_for_statistics(log)
      credits_used = log.payload_json&.dig("credits_used") || get_credits_for_action(log)
      
      activity_stats[action_key] ||= { action: action_key, count: 0, total_cost: 0 }
      activity_stats[action_key][:count] += 1
      activity_stats[action_key][:total_cost] += credits_used
    end
    
    # Sort by count (descending) and return all
    activity_stats.values.sort_by { |data| -data[:count] }
  end

  def calculate_top_credit_cost_activities(audit_logs)
    return [] unless current_company

    activity_stats = {}
    audit_logs.each do |log|
      action_key = get_action_key_for_statistics(log)
      credits_used = log.payload_json&.dig("credits_used") || get_credits_for_action(log)

      activity_stats[action_key] ||= { action: action_key, total_cost: 0, count: 0 }
      activity_stats[action_key][:total_cost] += credits_used
      activity_stats[action_key][:count] += 1
    end

    activity_stats.values.sort_by { |data| -data[:total_cost] }
  end

  def get_ai_activities
    return AuditLog.none unless current_company

    # Direct AI actions
    ai_actions = CreditService::LEDGER_ACTIONS
    
    # Root cause regeneration (UPDATE_CAPA_QUESTIONNAIRE with step: 'regenerate_root_cause')
    root_cause_regeneration = AuditLog.where(company_id: current_company.id)
                                      .where(action: "UPDATE_CAPA_QUESTIONNAIRE")
                                      .where("payload_json->>'step' = ?", "regenerate_root_cause")
    
    # Combine both
    AuditLog.where(company_id: current_company.id)
            .where(action: ai_actions)
            .or(root_cause_regeneration)
  end

  def get_action_key_for_statistics(log)
    # For root cause regeneration, use a specific key for statistics
    if log.action == "UPDATE_CAPA_QUESTIONNAIRE" && log.payload_json&.dig("step") == "regenerate_root_cause"
      "REGENERATE_ROOT_CAUSE"
    else
      log.action
    end
  end

  def get_credits_for_action(log)
    if log.action == "UPDATE_CAPA_QUESTIONNAIRE" && log.payload_json&.dig("step") == "regenerate_root_cause"
      return 0
    end

    action_key = get_action_key_for_statistics(log)
    CreditService.get_cost(action_key)
  end

  def require_company_user
    unless current_user&.company_user.present?
      redirect_to dashboard_path, alert: t('not_authorized')
      return
    end
  end

  def prevent_contributor_access
    if current_user&.company_user&.company_contributor?
      redirect_to dashboard_path, alert: t('not_authorized')
      return
    end
  end

  def require_company_admin_for_admin_tabs
    if ["overview", "credits", "credit_assignments"].include?(params[:tab]) && !current_user&.company_user&.company_admin?
      redirect_to dashboard_ai_insights_path(tab: "my_overview"), alert: t('not_authorized')
      return
    end
  end
end

