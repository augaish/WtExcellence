require "net/http"
require "json"
require "uri"

class OllamaClient
  def initialize(model: "qwen-wte", base_url: nil)
    @model = model.to_s.split("#").first.strip
    @base_url = ENV["OLLAMA_PROXY_URL"].presence || base_url || ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    @base_url = @base_url.chomp("/")
    @proxy_token = ENV["OLLAMA_PROXY_TOKEN"].presence
  end

  def generate(prompt, system: nil, max_tokens: 16000, num_ctx: nil, temperature: nil, top_p: nil, seed: nil)
    uri = URI("#{@base_url}/api/generate")

    options = {
      num_predict: max_tokens
    }
    # Default to deterministic (temperature 0) when not specified for backward compatibility
    options[:temperature] = temperature.nil? ? 0 : temperature
    options[:top_p] = top_p.nil? ? 1 : top_p
    options[:num_ctx] = num_ctx if num_ctx
    options[:seed] = seed if seed.is_a?(Integer)

    request_body = {
      model: @model,
      prompt: prompt,
      stream: false,
      options: options
    }
    request_body[:system] = system if system.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 300
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = request_body.to_json
    add_proxy_token!(request)

    http.use_ssl = (uri.scheme == "https")

    Rails.logger.info "Calling Ollama API: #{uri} with model: #{@model}"
    Rails.logger.info "Prompt length: #{prompt.length} chars"
    Rails.logger.info "System prompt length: #{system.length} chars" if system.present?

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Ollama API error: #{response.code} - #{response.message}"
      Rails.logger.error "Response body: #{response.body}"
      raise "Ollama API error: #{response.code} - #{response.message}"
    end

    parsed_response = JSON.parse(response.body)

    if parsed_response["error"]
      Rails.logger.error "Ollama API returned error: #{parsed_response['error']}"
      raise "Ollama API error: #{parsed_response['error']}"
    end

    content = parsed_response["response"]

    unless content
      Rails.logger.error "No response content from Ollama API"
      Rails.logger.error "Response: #{parsed_response.inspect}"
      raise "No response content from Ollama API"
    end

    Rails.logger.info "Successfully received response (#{content.length} chars)"
    content
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse Ollama response: #{e.message}"
    Rails.logger.error "Response body: #{response.body}" if defined?(response)
    raise
  rescue => e
    Rails.logger.error "Ollama API call failed: #{e.class} - #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    raise
  end

  def health_check
    uri = URI("#{@base_url}/api/tags")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 5
    http.open_timeout = 5

    request = Net::HTTP::Get.new(uri.request_uri)
    add_proxy_token!(request)
    http.use_ssl = (uri.scheme == "https")
    response = http.request(request)

    response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error "Ollama health check failed: #{e.message}"
    false
  end

  def show_model_info
    uri = URI("#{@base_url}/api/show")

    request_body = {
      name: @model
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 10
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = request_body.to_json
    add_proxy_token!(request)
    http.use_ssl = (uri.scheme == "https")

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Ollama API error: #{response.code} - #{response.message}"
      Rails.logger.error "Response body: #{response.body}"
      return nil
    end

    JSON.parse(response.body)
  rescue => e
    Rails.logger.error "Failed to get model info: #{e.message}"
    nil
  end

  private

  def add_proxy_token!(request)
    return if @proxy_token.blank?
    request["Authorization"] = "Bearer #{@proxy_token}"
  end
end
