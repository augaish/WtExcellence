# Secured proxy to Ollama. Deploy on the server where Ollama runs (inside the firewall).
# Call from local with OLLAMA_PROXY_URL + OLLAMA_PROXY_TOKEN in headers.
class OllamaProxyController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :restrict_www_to_homepage

  # POST/GET /ollama_proxy/api/generate, /ollama_proxy/api/chat, etc.
  def forward
    unless valid_proxy_token?
      head :unauthorized
      return
    end

    ollama_url = ENV["OLLAMA_URL"].presence || "http://localhost:11434"
    base = ollama_url.chomp("/")
    path = "/#{params[:path]}"
    path += "?#{request.query_string}" if request.query_string.present?
    uri = URI("#{base}#{path}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 300
    http.open_timeout = 10

    request_klass = request.get? ? Net::HTTP::Get : Net::HTTP::Post
    proxy_request = request_klass.new(uri.request_uri)
    proxy_request["Content-Type"] = request.content_type if request.content_type.present?
    proxy_request.body = request.raw_post if request.post? && request.raw_post.present?

    response = http.request(proxy_request)

    render body: response.body, status: response.code.to_i, content_type: response["Content-Type"].presence || "application/json"
  rescue => e
    Rails.logger.error "Ollama proxy error: #{e.message}"
    render plain: "Proxy error: #{e.message}", status: :bad_gateway
  end

  private

  def valid_proxy_token?
    secret = ENV["OLLAMA_PROXY_SECRET"].presence
    return false if secret.blank?

    token = request.headers["Authorization"]&.sub(/\ABearer\s+/i, "") ||
            request.headers["X-Ollama-Proxy-Token"]
    ActiveSupport::SecurityUtils.secure_compare(secret, token.to_s)
  end
end
