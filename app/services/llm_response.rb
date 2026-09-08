# Reads the text out of an OpenRouter chat completion, and says clearly when
# there is none.
#
# Three services each dug "choices/0/message/content" out of the reply and
# raised "Failed to extract content from API response" when it was nil. That
# message reached users as the whole explanation. Content is legitimately nil
# more often than that suggests: a reasoning model that put its output in
# another field, a reply cut off at the token limit, an error object with a
# 200 status. Each of those has a different remedy, so each is named.
module LlmResponse
  class Empty < StandardError
    attr_reader :reason

    def initialize(reason, message = nil)
      @reason = reason
      super(message || I18n.t("llm.errors.#{reason}", default: reason.to_s.humanize))
    end
  end

  module_function

  def content!(response)
    raise Empty.new(:no_response) if response.nil?
    return response if response.is_a?(String) && response.strip.present?

    unless response.is_a?(Hash)
      raise Empty.new(:unreadable, "Unexpected reply of type #{response.class}")
    end

    if response["error"]
      detail = response["error"].is_a?(Hash) ? response["error"]["message"] : response["error"]
      raise Empty.new(:provider_error, detail.to_s)
    end

    choice = response.dig("choices", 0) || {}
    message = choice["message"] || {}
    text = message["content"].presence || message["reasoning"].presence || choice["text"].presence

    if text.blank?
      reason = choice["finish_reason"].to_s == "length" ? :truncated : :empty
      raise Empty.new(reason)
    end

    # A reply that hit the token limit is usually unparseable JSON. Say so
    # rather than letting a parser explain it with a stray closing quote.
    raise Empty.new(:truncated) if choice["finish_reason"].to_s == "length" && looks_cut_off?(text)

    text
  end

  def looks_cut_off?(text)
    stripped = text.strip
    stripped.start_with?("{", "[") && !stripped.end_with?("}", "]")
  end
end
