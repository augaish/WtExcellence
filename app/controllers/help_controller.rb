class HelpController < Dashboard::BaseController
  # Ordered list of manual topics. Each renders app/views/help/topics/_<slug>.html.erb
  # and is titled via the help.topics.<slug> i18n key.
  TOPICS = %w[
    getting_started
    standards_assessment
    evidence
    capa
    risk_grc
    ai_features
    trust_center
    user_management
  ].freeze

  def index
    @topics = TOPICS
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
