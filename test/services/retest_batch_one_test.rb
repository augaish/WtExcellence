require "test_helper"

# Findings from the second review that concern trust in saved or generated data.
class RetestBatchOneTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Retest Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @process = @company.pp_processes.create!(name_en: "Purchase orders", level: 1, category: "core",
      frequency: "on_demand", automation_status: "partially_automated")
    @diagram = @company.pp_diagrams.create!(owner: @process, name: "PO flow")
  end

  # R10 — a hand-off between two internal performers is a lane crossing inside
  # one pool, which BPMN permits for sequence flow. Only an external participant
  # is a separate pool.
  test "a hand-off between two internal performers does not cross pools" do
    procurement = @diagram.elements.create!(element_type: "userTask", title: "Validate request", performer: "Procurement")
    finance = @diagram.elements.create!(element_type: "userTask", title: "Verify budget", performer: "Finance")
    flow = @diagram.flows.create!(from_element: procurement, to_element: finance, kind: "sequence")

    assert_not flow.crosses_pools?, "Procurement to Finance is a lane change, not a pool crossing"
    assert_equal procurement.pool, finance.pool
    assert_not_equal procurement.lane, finance.lane
  end

  test "a flow to an external participant still crosses pools" do
    internal = @diagram.elements.create!(element_type: "userTask", title: "Issue order", performer: "Procurement")
    supplier = @diagram.elements.create!(element_type: "userTask", title: "Deliver", performer: "Supplier", scope: "external")
    flow = @diagram.flows.create!(from_element: internal, to_element: supplier, kind: "sequence")

    assert flow.crosses_pools?
    assert_equal [ "Procurement", PpDiagramElement::EXTERNAL_POOL ], @diagram.lanes
  end

  test "the renderer draws one lane per performer and does not paint an internal hand-off red" do
    a = @diagram.elements.create!(element_type: "userTask", title: "Validate", performer: "Procurement")
    b = @diagram.elements.create!(element_type: "userTask", title: "Verify", performer: "Finance")
    @diagram.flows.create!(from_element: a, to_element: b, kind: "sequence")

    svg = ProcessDiagramRenderer.render(@diagram.reload)
    assert_includes svg, "Procurement"
    assert_includes svg, "Finance"
    assert_not_includes svg, "url(#arrow-bad)"
  end

  # R11 — completeness is not clearance.
  test "a high-priority finding is counted as blocking regardless of the score" do
    a = @diagram.elements.create!(element_type: "userTask", title: "Validate", performer: "Procurement")
    b = @diagram.elements.create!(element_type: "userTask", title: "Deliver", performer: "Supplier", scope: "external")
    @diagram.flows.create!(from_element: a, to_element: b, kind: "sequence")

    result = ProcessEvaluationService.evaluate_diagram(@diagram.reload)
    assert_operator result[:blocking_issues], :>, 0
  end

  test "a clean diagram has no blocking issues" do
    a = @diagram.elements.create!(element_type: "startEvent", title: "Start", performer: "Procurement")
    b = @diagram.elements.create!(element_type: "endEvent", title: "End", performer: "Procurement")
    @diagram.flows.create!(from_element: a, to_element: b, kind: "sequence")

    assert_equal 0, ProcessEvaluationService.evaluate_diagram(@diagram.reload)[:blocking_issues]
  end

  # R14 — nothing internal reaches the page.
  test "the process card prints enum values in words" do
    record = @company.pp_records.create!(record_type: "procedure", title_en: "PO procedure", pp_process: @process)
    card = RecordDocument.new(record).sections.find { |s| s.key == "process_card" }

    assert_equal "On demand", card.payload["frequency"]
    assert_equal "Partially automated", card.payload["automation_status"]
    assert_not_includes card.payload.values.join, "on_demand"
  end

  test "the classification table carries its definitions" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "A policy")
    table = RecordDocument.new(record).sections.find { |s| s.key == "classification" }

    table.payload.each do |row|
      assert_predicate row[:definition], :present?, "#{row[:label]} printed with an empty definition"
    end
  end

  test "the change log records what changed, not the description" do
    first = @company.pp_records.create!(record_type: "policy", title_en: "Policy", description: "Long description of the policy itself.")
    second = @company.pp_records.create!(record_type: "policy", title_en: "Policy", previous_version: first,
      version_number: 2, version_label: "v2", change_summary: "Added the legal review step.")

    log = RecordDocument.new(second).sections.find { |s| s.key == "change_log" }
    assert_equal [ I18n.t("record_document.initial_version"), "Added the legal review step." ],
      log.payload.map { |row| row[:description] }
    assert_not_includes log.payload.map { |row| row[:description] }.join, "Long description"
  end

  test "document dates print as dates, with no time" do
    assert_no_match(/12:00|AM|PM|الساعة/, I18n.l(Date.new(2026, 9, 8), format: :document, locale: :en))
    assert_no_match(/12:00|الساعة/, I18n.l(Date.new(2026, 9, 8), format: :document, locale: :ar))
  end
end
