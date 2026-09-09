# Images inside a governed document. On screen they are ordinary URLs; when the
# page is printed to PDF from a file on disk there is no server to fetch them
# from, so they are embedded as data URIs instead.
module DocumentHelper
  def document_logo_src
    return asset_path("logo.png") unless @inline_css

    path = Rails.root.join("app/assets/images/logo.png")
    path.exist? ? data_uri("image/png", path.binread) : ""
  end

  def document_brand_logo_src(company)
    logo = company&.brand_logo
    return nil unless logo&.attached?
    return dashboard_branding_logo_path unless @inline_css

    data_uri(logo.content_type.presence || "image/png", logo.download)
  rescue => e
    Rails.logger.warn "Brand logo could not be embedded: #{e.class}: #{e.message}"
    nil
  end

  private

  def data_uri(type, bytes)
    "data:#{type};base64,#{Base64.strict_encode64(bytes)}"
  end
end
