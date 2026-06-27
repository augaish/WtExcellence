class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]
  layout false

  def index
    host = request.host.downcase

    # app.wtexcel.com and test.* → always go to dashboard/overview (login required there)
    if host.include?("test") || host.include?("app")
      redirect_to dashboard_overview_path, status: :see_other
      return
    end

    # www.wtexcel.com (and wtexcel.com) → presentation only, show homepage
    # Public homepage - no authentication required
  end
end
