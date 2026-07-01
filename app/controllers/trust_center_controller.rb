class TrustCenterController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :show ]
  layout "public"

  def show
    @company = Company.find_by(id: params[:company_id])

    unless @company&.trust_center_enabled?
      render "not_found", status: :not_found
      return
    end

    @company_standards = @company.company_standards
      .active
      .includes(:standard)
      .joins(:standard)
      .order("standards.code ASC")
  end
end
