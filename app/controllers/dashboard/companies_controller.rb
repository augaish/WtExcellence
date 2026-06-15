class Dashboard::CompaniesController < Dashboard::BaseController
  before_action :require_platform_admin

  def index
    @companies = Company.includes(:company_users, :company_standards)
                        .order(:name)
  end

  private

  def require_platform_admin
    unless current_user&.platform_admin?
      redirect_to root_path, alert: "You don't have permission to access this page.", status: :see_other
    end
  end
end
