require "test_helper"

class ProcessDiagramRendererTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Render Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Onboarding", pp_process: level_two_process(@company))
    @diagram = @company.pp_diagrams.create!(owner: @record, name: "Onboarding")
  end

  def add(**attrs)
    @diagram.elements.create!({ element_type: "manualTask", title: "Step", performer: "HR" }.merge(attrs))
  end

  test "an empty diagram renders a placeholder rather than blowing up" do
    svg = ProcessDiagramRenderer.render(@diagram)

    assert_includes svg, "<svg"
    assert_includes svg, I18n.t("architect.empty_diagram")
  end

  test "renders one lane per pool" do
    add(performer: "HR")
    add(performer: "Finance")
    add(performer: "Supplier", scope: "external")

    svg = ProcessDiagramRenderer.render(@diagram.reload)

    assert_includes svg, "HR"
    assert_includes svg, "Finance"
    assert_includes svg, I18n.t("architect.external_pool")
  end

  test "places each element in its performer's lane" do
    hr = add(performer: "HR")
    finance = add(performer: "Finance")

    layout = ProcessDiagramRenderer.new(@diagram.reload).layout

    assert_equal 0, layout[hr.id][:lane]
    assert_equal 1, layout[finance.id][:lane]
    # Elements advance left to right in author order.
    assert layout[finance.id][:column] > layout[hr.id][:column]
  end

  test "a sequence flow crossing pools is drawn as an error" do
    inside = add(performer: "HR")
    outside = add(performer: "Supplier", scope: "external")
    @diagram.flows.create!(from_element: inside, to_element: outside, kind: "sequence")

    svg = ProcessDiagramRenderer.render(@diagram.reload)

    assert_includes svg, "url(#arrow-bad)", "an invalid cross-pool sequence flow must be flagged"
  end

  test "a message flow to an external participant is drawn dashed, not as an error" do
    inside = add(performer: "HR")
    outside = add(performer: "Supplier", scope: "external")
    @diagram.flows.create!(from_element: inside, to_element: outside, kind: "message")

    svg = ProcessDiagramRenderer.render(@diagram.reload)

    assert_includes svg, "stroke-dasharray"
    # The error marker is always DEFINED in <defs>; what matters is that no flow uses it.
    refute_includes svg, "url(#arrow-bad)"
    assert_includes svg, "url(#arrow-msg)"
  end

  test "events, gateways and tasks get distinct shapes" do
    add(element_type: "startEvent", title: "Start")
    add(element_type: "gateway", title: "Approved?")
    add(element_type: "userTask", title: "Review")

    svg = ProcessDiagramRenderer.render(@diagram.reload)

    assert_includes svg, "<circle", "events render as circles"
    assert_includes svg, "<polygon", "gateways render as diamonds"
    assert_includes svg, "<rect", "tasks render as boxes"
  end

  test "escapes titles so a diagram cannot inject markup" do
    add(title: "<script>alert(1)</script>", performer: "HR")

    svg = ProcessDiagramRenderer.render(@diagram.reload)

    refute_includes svg, "<script>"
    assert_includes svg, "&lt;script&gt;"
  end

  test "uses the house palette" do
    add(element_type: "userTask", title: "Review")
    svg = ProcessDiagramRenderer.render(@diagram.reload)

    assert_includes svg, ProcessDiagramRenderer::PRIMARY
  end

  test "the canvas grows with the number of elements" do
    add
    small = ProcessDiagramRenderer.new(@diagram.reload).render
    5.times { add }
    large = ProcessDiagramRenderer.new(@diagram.reload).render

    small_width = small[/viewBox="0 0 (\d+)/, 1].to_i
    large_width = large[/viewBox="0 0 (\d+)/, 1].to_i
    assert large_width > small_width
  end
end
