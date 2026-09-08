require "test_helper"

# R07/R08 — every AI reply was read with one line and one generic error.
class LlmResponseTest < ActiveSupport::TestCase
  test "plain content is returned" do
    assert_equal "hello", LlmResponse.content!({ "choices" => [ { "message" => { "content" => "hello" } } ] })
  end

  test "a reasoning model's output is found where it put it" do
    reply = { "choices" => [ { "message" => { "content" => nil, "reasoning" => "{\"q\":1}" } } ] }
    assert_equal "{\"q\":1}", LlmResponse.content!(reply)
  end

  test "no reply at all is named as such" do
    error = assert_raises(LlmResponse::Empty) { LlmResponse.content!(nil) }
    assert_equal :no_response, error.reason
  end

  test "a provider error is surfaced with its own message" do
    error = assert_raises(LlmResponse::Empty) { LlmResponse.content!({ "error" => { "message" => "rate limited" } }) }
    assert_equal :provider_error, error.reason
    assert_includes error.message, "rate limited"
  end

  test "a reply cut off at the token limit is reported as truncated, not as a parse error" do
    reply = { "choices" => [ { "finish_reason" => "length", "message" => { "content" => "{\"question\": \"Why did" } } ] }
    error = assert_raises(LlmResponse::Empty) { LlmResponse.content!(reply) }
    assert_equal :truncated, error.reason
  end

  test "an empty message is reported as empty" do
    error = assert_raises(LlmResponse::Empty) { LlmResponse.content!({ "choices" => [ { "message" => { "content" => "" } } ] }) }
    assert_equal :empty, error.reason
  end

  test "every reason has a user-facing sentence in both languages" do
    %i[no_response unreadable provider_error empty truncated].each do |reason|
      I18n.available_locales.each do |locale|
        assert_predicate I18n.t("llm.errors.#{reason}", locale: locale, default: ""), :present?, "#{reason} #{locale}"
      end
    end
  end
end
