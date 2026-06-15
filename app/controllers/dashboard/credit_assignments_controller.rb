class Dashboard::CreditAssignmentsController < Dashboard::BaseController
  before_action :require_company_admin
  before_action :set_company_user, only: :update

  def update
    new_balance = credit_assignment_params[:assigned_credits]

    CreditService.set_user_credit_balance!(@company_user, new_balance)

    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                notice: I18n.t("credit_assignment_updated"),
                status: :see_other
  rescue CreditService::InsufficientCreditsError => e
    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                alert: e.message,
                status: :see_other
  rescue CreditService::InvalidAssignmentError => e
    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                alert: e.message,
                status: :see_other
  end

  def split_equally
    company = current_company

    unless company
      redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                  alert: I18n.t("company_not_found"),
                  status: :see_other and return
    end

    company_users = company.company_users.includes(:user)
    if company_users.blank?
      redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                  alert: I18n.t("credits_split_equally_no_users"),
                  status: :see_other and return
    end

    available_credits = company.credits.to_i
    if available_credits <= 0
      redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                  alert: I18n.t("credits_split_equally_no_credits"),
                  status: :see_other and return
    end

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

    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                notice: I18n.t("credits_split_equally_success"),
                status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                alert: I18n.t("credits_split_equally_error", message: e.message),
                status: :see_other
  end

  def reset_assignments
    company = current_company

    unless company
      redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                  alert: I18n.t("company_not_found"),
                  status: :see_other and return
    end

    company_users = company.company_users.includes(:user)
    if company_users.blank?
      redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                  alert: I18n.t("credits_reset_no_users"),
                  status: :see_other and return
    end

    Company.transaction do
      company.lock!
      locked_users = company.company_users.lock.to_a

      total_returned = locked_users.sum { |u| u.assigned_credits.to_i }
      locked_users.each { |u| u.update!(assigned_credits: 0) }
      company.update!(credits: company.credits.to_i + total_returned)
    end

    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                notice: I18n.t("credits_reset_success"),
                status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                alert: I18n.t("credits_reset_error", message: e.message),
                status: :see_other
  end

  private

  def set_company_user
    @company_user = current_company&.company_users&.includes(:user)&.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_ai_insights_path(tab: "credit_assignments"),
                alert: I18n.t("company_user_not_found"),
                status: :see_other
    return
  end

  def credit_assignment_params
    params.require(:company_user).permit(:assigned_credits)
  end
end

