class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.

  before_action :restrict_www_to_homepage
  before_action :authenticate_user!
  skip_before_action :authenticate_user!, only: [ :switch_language ]

  allow_browser versions: :modern

  # I18n and locale support
  around_action :switch_locale
  before_action :set_locale_info


  include Pagy::Backend


  # Language switching action
  def switch_language
    new_locale = params[:locale]&.to_sym

    if I18n.available_locales.include?(new_locale)
      session[:locale] = new_locale
      # Force full page reload by redirecting with status :see_other
      redirect_to request.referer || root_path, allow_other_host: false, status: :see_other
    else
      redirect_back(fallback_location: root_path, alert: "Invalid language", status: :see_other)
    end
  end

  private

  # Restrict www.<APP_DOMAIN> to only show homepage
  def restrict_www_to_homepage
    host = request.host.downcase
    app_domain = ENV.fetch("APP_DOMAIN", "wtexcellence.com")

    # Check if host is www.<APP_DOMAIN> or <APP_DOMAIN> (but not test or app)
    if (host == "www.#{app_domain}" || host == app_domain) &&
       !host.include?("test") && !host.include?("app")
      # Allow root path, waitlist routes, and language switching
      allowed_paths = ["/", root_path, "/waitlist", "/waitlist/success"]
      # Also allow language switching routes (e.g., /language/en, /language/ar)
      is_language_route = request.path.match?(%r{^/language/[a-z]{2}$})
      # If not on allowed path, redirect to homepage
      unless allowed_paths.include?(request.path) || is_language_route
        redirect_to root_path, status: :see_other
      end
    end
  end

  # Detect and set locale from params, session, or browser
  def switch_locale(&action)
    locale = params[:locale] || session[:locale] || extract_locale_from_accept_language_header || I18n.default_locale
    locale = I18n.default_locale unless I18n.available_locales.include?(locale.to_sym)

    I18n.with_locale(locale, &action)
    session[:locale] = locale
  end

  # Extract locale from Accept-Language header
  def extract_locale_from_accept_language_header
    return nil unless request.env["HTTP_ACCEPT_LANGUAGE"]

    request.env["HTTP_ACCEPT_LANGUAGE"].scan(/^[a-z]{2}/).first&.to_sym
  end

  # Set locale information for views
  def set_locale_info
    @current_locale = I18n.locale
    @is_rtl = @current_locale == :ar
  end

  # Helper method for views
  def rtl?
    @is_rtl
  end




  # Redirect after sign in — always send to dashboard overview (app/test); overview controller redirects if no access
  def after_sign_in_path_for(resource)
    role_display = get_user_role_display(resource)
    flash[:notice] = "Welcome back #{resource.name}!#{role_display}"

    # On first login (until the user skips/closes it) send them straight to the
    # user manual so they get oriented before using the app.
    return help_path(welcome: 1) if resource.is_a?(User) && !resource.user_manual_seen?

    dashboard_overview_path
  end

  # Get user role display text for notifications
  def get_user_role_display(user)
    return " (Super Admin)" if user.super_admin?
    return " (Delegated Admin)" if user.delegated_admin?

    # Get the user's company role (users belong to exactly one company)
    company_user = user.company_user
    return "" unless company_user

    role_name = format_role_name(company_user.role)
    " (#{role_name})"
  end

  # Format role name for display (remove 'company_' prefix and capitalize)
  def format_role_name(role)
    return "" if role.blank?

    # Remove 'company_' prefix if present
    formatted = role.gsub(/^company_/, "")
    # Capitalize first letter
    formatted.humanize
  end

  # Redirect after sign out
  def after_sign_out_path_for(resource_or_scope)
    new_user_session_path
  end
end
