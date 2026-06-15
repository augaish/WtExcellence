class Dashboard::CreditChangesController < Dashboard::BaseController
  before_action :require_super_admin_or_delegated_admin
  before_action :require_super_admin_or_credit_permission, only: [:update, :update_company, :update_company_user, :reset_company_credits, :split_company_credits]

  def index
    AiActionCredit.ensure_defaults!
    @ai_action_credits = AiActionCredit.order(:action_type)
    @companies = Company.includes(:company_users).order(:name)
    @active_tab = permitted_tab_param
  end

  def update
    @ai_action_credit = AiActionCredit.find(params[:id])

    # Parse JSON body if it's a JSON request
    if request.content_type&.include?("application/json")
      json_params = JSON.parse(request.body.read)
      credit_cost = json_params["credit_cost"]
    else
      credit_cost = params[:credit_cost]
    end

    if @ai_action_credit.update(credit_cost: credit_cost.to_i)
      # Clear the cache so updated costs are reflected immediately
      CreditService.clear_cache

      respond_to do |format|
        format.json { render json: { success: true, credit_cost: @ai_action_credit.credit_cost } }
        format.html { redirect_to dashboard_credit_changes_path, notice: "Credit cost updated successfully." }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: @ai_action_credit.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to dashboard_credit_changes_path, alert: "Failed to update credit cost: #{@ai_action_credit.errors.full_messages.join(', ')}" }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { success: false, errors: [ "Credit action not found" ] }, status: :not_found }
      format.html { redirect_to dashboard_credit_changes_path, alert: "Credit action not found.", status: :see_other }
    end
  rescue JSON::ParserError
    respond_to do |format|
      format.json { render json: { success: false, errors: [ "Invalid JSON" ] }, status: :unprocessable_entity }
      format.html { redirect_to dashboard_credit_changes_path, alert: "Invalid request.", status: :see_other }
    end
  end

  def update_company
    company = Company.find(params[:id])
    credits_value = company_credit_value_from_params

    if credits_value.nil? || credits_value.negative?
      return respond_with_company_error(I18n.t("invalid_company_credit_amount"))
    end

    CreditService.set_company_credits!(company, credits_value)
    assigned_total = company.company_users.sum(:assigned_credits)

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          credits: company.credits,
          assigned_total: assigned_total,
          total_credits: company.credits + assigned_total
        }
      end
      format.html do
        redirect_to dashboard_credit_changes_path(tab: "company_credits"),
                    notice: I18n.t("company_credits_updated_successfully"),
                    status: :see_other
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_with_company_error(I18n.t("company_not_found"), status: :not_found)
  rescue CreditService::InvalidAssignmentError => e
    respond_with_company_error(e.message)
  end

  def company_users
    company = Company.includes(company_users: :user).find(params[:id])
    company_users = ordered_company_users(company.company_users.includes(:user))
    assigned_total = company_users.sum { |cu| cu.assigned_credits.to_i }

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          company: {
            id: company.id,
            name: company.name,
            credits: company.credits,
            assigned_total: assigned_total,
            total_credits: company.credits + assigned_total,
            split_users_url: dashboard_credit_changes_company_split_users_path(company),
            reset_users_url: dashboard_credit_changes_company_reset_users_path(company)
          },
          users: company_users.map { |cu| serialize_company_user(cu) }
        }
      end
      format.html do
        redirect_to dashboard_credit_changes_path(tab: "company_credits"),
                    notice: I18n.t("company_users_loaded"),
                    status: :see_other
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_with_company_error(I18n.t("company_not_found"), status: :not_found)
  end

  def split_company_credits
    company = Company.find(params[:id])
    users = company.company_users.includes(:user)

    return render_company_user_action_error(I18n.t("credits_split_equally_no_users")) if users.blank?

    available_credits = company.credits.to_i
    return render_company_user_action_error(I18n.t("credits_split_equally_no_credits")) if available_credits <= 0

    locked_users = []
    Company.transaction do
      company.lock!
      locked_users = company.company_users.lock.to_a

      user_count = locked_users.length
      base_share = available_credits / user_count
      remainder = available_credits % user_count

      locked_users.each_with_index do |company_user, index|
        increment = base_share + (index < remainder ? 1 : 0)
        next if increment.zero?

        company_user.update!(assigned_credits: company_user.assigned_credits.to_i + increment)
      end

      company.update!(credits: 0)
    end

    render_company_users_success(company, locked_users, message: I18n.t("credits_split_equally_success"))
  rescue ActiveRecord::RecordNotFound
    render_company_user_action_error(I18n.t("company_not_found"), status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render_company_user_action_error(I18n.t("credits_split_equally_error", message: e.message))
  end

  def reset_company_credits
    company = Company.find(params[:id])
    users = company.company_users.includes(:user)

    return render_company_user_action_error(I18n.t("credits_reset_no_users")) if users.blank?

    locked_users = []
    Company.transaction do
      company.lock!
      locked_users = company.company_users.lock.to_a

      total_returned = locked_users.sum { |u| u.assigned_credits.to_i }
      locked_users.each { |u| u.update!(assigned_credits: 0) }
      company.update!(credits: company.credits.to_i + total_returned)
    end

    render_company_users_success(company, locked_users, message: I18n.t("credits_reset_success"))
  rescue ActiveRecord::RecordNotFound
    render_company_user_action_error(I18n.t("company_not_found"), status: :not_found)
  rescue ActiveRecord::RecordInvalid, StandardError => e
    render_company_user_action_error(I18n.t("credits_reset_error", message: e.message))
  end

  def update_company_user
    company = Company.find(params[:company_id])
    company_user = company.company_users.includes(:user).find(params[:id])
    assigned_credits = company_user_credit_value_from_params

    if assigned_credits.nil? || assigned_credits.negative?
      return respond_with_company_user_error(I18n.t("invalid_user_credit_amount"), company_user: company_user)
    end

    CreditService.set_user_credit_balance!(company_user, assigned_credits)

    respond_to do |format|
      format.json do
        company.reload
        assigned_total = company.company_users.sum(:assigned_credits)
        render json: {
          success: true,
          company: {
            id: company.id,
            credits: company.credits,
            assigned_total: assigned_total,
            total_credits: company.credits + assigned_total,
            split_users_url: dashboard_credit_changes_company_split_users_path(company),
            reset_users_url: dashboard_credit_changes_company_reset_users_path(company)
          },
          user: serialize_company_user(company_user.reload)
        }
      end
      format.html do
        redirect_to dashboard_credit_changes_path(tab: "company_credits"),
                    notice: I18n.t("user_credits_updated_successfully"),
                    status: :see_other
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_with_company_user_error(I18n.t("company_user_not_found"), status: :not_found)
  rescue CreditService::InvalidAssignmentError, CreditService::InsufficientCreditsError => e
    respond_with_company_user_error(e.message, company_user: company_user)
  end

  private

  def require_super_admin_or_delegated_admin
    return if current_user&.super_admin? || current_user&.delegated_admin?

    error_message = "You don't have permission to access this page."
    respond_to do |format|
      format.json do
        render json: {
          success: false,
          errors: [error_message],
          message: error_message,
          type: "error"
        }, status: :forbidden
      end
      format.html do
        redirect_to root_path, alert: error_message, status: :see_other
      end
    end
    false
  end

  def require_super_admin_or_credit_permission
    return if current_user&.super_admin? || current_user&.can_increase_credit?

    error_message = "You don't have permission to access this page."
    notification_html = render_to_string(
      partial: "shared/notification",
      locals: { message: error_message, type: :error, animated: true },
      formats: [:html]
    )

    respond_to do |format|
      format.json do
        render json: {
          success: false,
          errors: [error_message],
          message: error_message,
          type: "error",
          notification_html: notification_html
        }, status: :forbidden
      end
      format.html do
        redirect_to root_path, alert: error_message, status: :see_other
      end
    end
    false
  end

  def permitted_tab_param
    tab = params[:tab].to_s
    return tab if %w[ai_actions company_credits].include?(tab)

    "ai_actions"
  end

  def company_credit_value_from_params
    value =
      if request.content_type&.include?("application/json")
        begin
          json_params = JSON.parse(request.body.read)
          json_params["credits"] || json_params.dig("company", "credits")
        rescue JSON::ParserError
          nil
        end
      else
        params[:credits] || params.dig(:company, :credits)
      end

    return nil if value.nil?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def respond_with_company_error(message, status: :unprocessable_entity)
    respond_to do |format|
      format.json { render json: { success: false, errors: Array(message) }, status: status }
      format.html do
        redirect_to dashboard_credit_changes_path(tab: "company_credits"),
                    alert: message,
                    status: :see_other
      end
    end
  end

  def company_user_credit_value_from_params
    value =
      if request.content_type&.include?("application/json")
        begin
          json_params = JSON.parse(request.body.read)
          json_params["assigned_credits"] || json_params.dig("company_user", "assigned_credits")
        rescue JSON::ParserError
          nil
        end
      else
        params[:assigned_credits] || params.dig(:company_user, :assigned_credits)
      end

    return nil if value.nil?

    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def respond_with_company_user_error(message, status: :unprocessable_entity, company_user: nil)
    respond_to do |format|
      format.json do
        render json: {
          success: false,
          errors: Array(message),
          user: company_user ? serialize_company_user(company_user) : nil
        }.compact,
               status: status
      end
      format.html do
        redirect_to dashboard_credit_changes_path(tab: "company_credits"),
                    alert: message,
                    status: :see_other
      end
    end
  end

  def serialize_company_user(company_user)
    {
      id: company_user.id,
      name: company_user.user&.name || I18n.t("unknown_user"),
      email: company_user.user&.email,
      role: company_user.role,
      company_id: company_user.company_id,
      assigned_credits: company_user.assigned_credits,
      update_url: dashboard_credit_changes_company_user_path(company_user.company, company_user)
    }
  end

  def render_company_users_success(company, users, message: nil)
    users = ordered_company_users(users)
    assigned_total = users.sum { |u| u.assigned_credits.to_i }
    total_credits = company.credits.to_i + assigned_total
    render json: {
      success: true,
      notice: message,
      company: {
        id: company.id,
        name: company.name,
        credits: company.credits,
        assigned_total: assigned_total,
        total_credits: total_credits,
        split_users_url: dashboard_credit_changes_company_split_users_path(company),
        reset_users_url: dashboard_credit_changes_company_reset_users_path(company)
      },
      users: users.map { |u| serialize_company_user(u) }
    }
  end

  def render_company_user_action_error(message, status: :unprocessable_entity)
    render json: { success: false, errors: Array(message) }, status: status
  end

  def ordered_company_users(scope)
    Array(scope).sort_by do |u|
      (u.user&.name || "").downcase
    end
  end
end

