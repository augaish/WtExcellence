require "test_helper"

class StandardIngestionServiceTest < ActiveSupport::TestCase
  # Minimal stand-ins so we never touch Active Storage or the network.
  FakeBlob = Struct.new(:data, :name) do
    def download = data
    def filename = name
  end
  FakeFile = Struct.new(:blob)

  def build_service(pdf_bytes: "%PDF-1.4 fake", pages: 5, client:)
    svc = StandardIngestionService.allocate
    svc.instance_variable_set(:@pdf_file, FakeFile.new(FakeBlob.new(pdf_bytes, "kaqa.pdf")))
    svc.instance_variable_set(:@model, "anthropic/claude-sonnet-4.5")
    svc.instance_variable_set(:@client, client)
    svc.instance_variable_set(:@on_progress, nil)
    svc.define_singleton_method(:pdf_page_count) { |_| pages }
    svc.define_singleton_method(:save_llm_response) { |_| nil }
    svc
  end

  test "native PDF path parses model.criteria from Claude" do
    canned = {
      "choices" => [ { "message" => { "content" => {
        "model" => { "name_en" => "KAQA", "criteria" => [
          { "id" => 1, "name_en" => "Leadership", "name_ar" => "القيادة", "subcriteria" => [] }
        ] }
      }.to_json } } ]
    }
    client = Object.new
    client.define_singleton_method(:complete) do |_messages, **opts|
      # Drive the streaming proc with the JSON split across two chunks.
      json = canned.dig("choices", 0, "message", "content")
      opts[:stream].call({ "choices" => [ { "delta" => { "content" => json[0, 20] } } ] })
      opts[:stream].call({ "choices" => [ { "delta" => { "content" => json[20..] } } ] })
      nil
    end

    svc = build_service(client: client)
    result = svc.process_pdf_via_claude

    assert_nil result["error"], "expected success, got #{result['error']}"
    assert_equal 1, result.dig("model", "criteria").length
    assert_equal "Leadership", result.dig("model", "criteria", 0, "name_en")
  end

  test "native PDF path returns error hash when Claude errors" do
    client = Object.new
    client.define_singleton_method(:complete) { |_messages, **_opts| raise "402 Payment Required" }
    # (raises before any streaming)

    svc = build_service(client: client)
    result = svc.process_pdf_via_claude

    assert_equal [], result.dig("model", "criteria")
    assert_match(/402/, result["error"])
  end

  test "rejects a PDF over the page limit" do
    client = Object.new
    client.define_singleton_method(:complete) { |*_| flunk("should not call Claude") }

    svc = build_service(pages: 500, client: client)
    result = svc.process_pdf_via_claude
    assert_match(/page limit|500 pages/, result["error"])
  end

  test "build_pdf_prompt covers the key rules" do
    svc = StandardIngestionService.allocate
    prompt = svc.send(:build_pdf_prompt)
    assert_match(/ATTACHED/, prompt)
    assert_match(/table of contents/i, prompt)
    assert_match(/never be left empty|never left empty|translate/i, prompt)
  end
end
