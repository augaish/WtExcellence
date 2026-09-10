class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index ]
  layout false

  def index
    host = request.host.downcase

    # The page is rendered per language; a cache in front of the app must not
    # hand one language's copy to the other's visitors.
    response.headers["Cache-Control"] = "no-store"
    response.headers["Vary"] = "Cookie, Accept-Language"

    # app.wtexcellence.com and test.* → always go to dashboard/overview (login required there)
    if host.include?("test") || host.include?("app")
      redirect_to dashboard_overview_path, status: :see_other
      return
    end

    # The policy pages open from the homepage URL too (/?page=privacy), so a
    # link keeps working even when a proxy in front of the app only knows "/".
    @slug = params[:page].to_s
    if PagesController::SLUGS.include?(@slug)
      render "pages/#{@slug}", layout: "public"
      return
    end

    # www.wtexcellence.com (and wtexcellence.com) → presentation only, show homepage
    # Public homepage - no authentication required
  end
end
