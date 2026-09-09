# Company branding: the logo shown beside the WTE mark, and the colours used for
# this company's own surfaces and generated documents. Company-scoped and
# admin-only, so it is kept apart from the user's own general settings.
class Dashboard::BrandingController < Dashboard::BaseController
  before_action :ensure_can_manage_branding, except: [ :logo ]
  before_action :set_company

  def index
  end

  # The logo is served by the app itself, whatever storage holds it, so a
  # page never shows a broken image because of how a storage URL was signed.
  def logo
    logo = @company.brand_logo
    return head :not_found unless logo.attached?

    expires_in 10.minutes, public: false
    send_data logo.download, type: logo.content_type.presence || "image/png", disposition: "inline", filename: logo.filename.to_s
  end

  def update
    return if prevent_viewer_action

    @company.brand_logo.purge if params[:remove_brand_logo] == "1"

    if @company.update(branding_params)
      log_branding_change
      redirect_to dashboard_branding_path, notice: t("branding.updated")
    else
      flash.now[:alert] = @company.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_company
    @company = current_company
    redirect_to dashboard_overview_path, alert: t("branding.no_company") if @company.nil?
  end

  def ensure_can_manage_branding
    return if current_user&.super_admin? || current_user&.delegated_admin?
    return if current_user&.company_user&.has_admin_privileges?

    redirect_to dashboard_overview_path, alert: t("branding.not_permitted")
  end

  # A blank colour clears the setting and returns the company to the WTE
  # palette, so the fields are permitted even when empty.
  def branding_params
    params.require(:company).permit(:brand_logo, :brand_primary_color, :brand_accent_color)
  end

  def log_branding_change
    AuditLogService.log_action(
      actor_user: current_user,
      company: @company,
      action: "UPDATE_COMPANY_BRANDING",
      entity_type: "company",
      entity_id: @company.id,
      payload: {
        brand_primary_color: @company.brand_primary_color,
        brand_accent_color: @company.brand_accent_color,
        logo_attached: @company.brand_logo.attached?
      }
    )
  end
end
