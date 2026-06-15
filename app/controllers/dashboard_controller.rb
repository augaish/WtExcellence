class DashboardController < Dashboard::BaseController
  def index
    redirect_to dashboard_overview_path
  end

  def capa_management
  end
end
