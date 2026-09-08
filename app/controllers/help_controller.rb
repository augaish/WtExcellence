class HelpController < Dashboard::BaseController
  # Ordered list of manual topics. Each renders app/views/help/topics/_<slug>.html.erb
  # and is titled via the help.topics.<slug> i18n key.
  TOPICS = %w[
    getting_started
    standards_assessment
    evidence
    capa
    org_and_processes
    policies_procedures
    delegation_of_authority
    risk_grc
    ai_features
    trust_center
    user_management
  ].freeze

  def index
    @topics = TOPICS
    # First-run welcome banner (shown only when arriving from the post-login
    # redirect and the user hasn't dismissed the manual yet).
    @welcome = params[:welcome].present? && !current_user.user_manual_seen?
  end

  # Marks the manual as seen so it stops auto-showing on future logins, then
  # returns the user to the dashboard.
  def dismiss
    current_user.mark_user_manual_seen!

    respond_to do |format|
      format.html { redirect_to dashboard_overview_path, status: :see_other }
      format.json { render json: { ok: true } }
    end
  end

  def show
    @slug = params[:slug]

    unless TOPICS.include?(@slug)
      redirect_to help_path, alert: t("help.topic_not_found")
      return
    end

    @topics = TOPICS
  end
end
