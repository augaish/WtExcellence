# The public pages an enterprise buyer looks for before talking to anyone:
# privacy, terms, security and who we are. Bilingual, no sign-in.
class PagesController < ApplicationController
  skip_before_action :authenticate_user!
  layout "public"

  SLUGS = %w[privacy terms security about].freeze

  def show
    @slug = params[:slug]
    head :not_found and return unless SLUGS.include?(@slug)

    render "pages/#{@slug}"
  end
end
