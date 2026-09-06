require "test_helper"

class PpDiagramTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Dia Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Onboarding")
    @diagram = @company.pp_diagrams.create!(owner: @record, name: "Onboarding process")
  end

  def add_element(**attrs)
    @diagram.elements.create!({ element_type: "manualTask", title: "Step", performer: "HR" }.merge(attrs))
  end

  test "requires a known element type" do
    refute @diagram.elements.new(element_type: "wormhole").valid?
    PpDiagramElement::TYPES.each do |type|
      assert @diagram.elements.new(element_type: type).valid?, "#{type} should be valid"
    end
  end

  test "the pool is the performer, and external elements get their own pool" do
    internal = add_element(performer: "Finance")
    external = add_element(performer: "Supplier", scope: "external")
    unnamed = add_element(performer: nil)

    assert_equal "Finance", internal.pool
    assert_equal PpDiagramElement::EXTERNAL_POOL, external.pool
    assert_equal PpDiagramElement::DEFAULT_POOL, unnamed.pool
  end

  test "pools list internal lanes first and external last" do
    add_element(performer: "Finance")
    add_element(performer: "Supplier", scope: "external")
    add_element(performer: "HR")

    assert_equal [ "Finance", "HR", PpDiagramElement::EXTERNAL_POOL ], @diagram.reload.pools
  end

  test "a flow cannot connect an element to itself" do
    element = add_element
    flow = @diagram.flows.new(from_element: element, to_element: element, kind: "sequence")

    refute flow.valid?
  end

  test "a flow cannot span two diagrams" do
    other_diagram = @company.pp_diagrams.create!(owner: @record, name: "Other")
    mine = add_element
    theirs = other_diagram.elements.create!(element_type: "manualTask", title: "Elsewhere")

    flow = @diagram.flows.new(from_element: mine, to_element: theirs, kind: "sequence")
    refute flow.valid?
  end

  test "crosses_pools? detects a sequence flow spanning participants" do
    inside = add_element(performer: "HR")
    outside = add_element(performer: "Supplier", scope: "external")

    flow = @diagram.flows.create!(from_element: inside, to_element: outside, kind: "sequence")
    assert flow.crosses_pools?

    same = @diagram.flows.create!(from_element: inside, to_element: add_element(performer: "HR"), kind: "sequence")
    refute same.crosses_pools?
  end

  # The contract is what Phase 5 consumes — the field names must match exactly.
  test "to_contract emits the evaluation shape" do
    @diagram.update!(trigger_text: "Request received", inputs_summary: "Form", outputs_summary: "Signed policy")
    start = add_element(element_type: "startEvent", title: "Start", performer: "HR")
    task = add_element(element_type: "userTask", title: "Review", performer: "HR",
      description: "Check details", input: "Draft", output: "Reviewed draft")
    @diagram.flows.create!(from_element: start, to_element: task, kind: "sequence")

    contract = @diagram.reload.to_contract

    assert_equal %w[elements flows trigger inputsSummary outputsSummary], contract.keys
    element = contract["elements"].last
    assert_equal %w[type title performer desc input output trigger scope flowLabel], element.keys
    assert_equal "userTask", element["type"]
    assert_equal "Check details", element["desc"]
    assert_equal "Draft", element["input"]

    flow = contract["flows"].first
    assert_equal "sequence", flow["kind"]
    assert_equal({ "pool" => "HR" }, flow["from"])
    assert_equal "Request received", contract["trigger"]
  end

  test "summary fields fall back to the owning process card" do
    process = @company.pp_processes.create!(name_en: "Hiring", level: 1,
      trigger_text: "Vacancy approved", inputs: "Job description", outputs: "Signed contract")
    diagram = @company.pp_diagrams.create!(owner: process, name: "Hiring")

    summary = diagram.effective_summary
    assert_equal "Vacancy approved", summary[:trigger]
    assert_equal "Job description", summary[:inputs]
  end

  test "a diagram cannot belong to another company's record" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "policy", title_en: "Foreign")

    refute @company.pp_diagrams.new(owner: foreign, name: "X").valid?
  end

  test "diagrams list most recent first" do
    older = @diagram
    newer = @company.pp_diagrams.create!(owner: @record, name: "Newer")
    newer.update_column(:created_at, older.created_at + 1.day)

    assert_equal [ newer.id, older.id ], @record.reload.diagrams.map(&:id)
  end

  test "deleting a diagram removes its elements and flows" do
    a = add_element
    b = add_element
    @diagram.flows.create!(from_element: a, to_element: b, kind: "sequence")

    assert_difference -> { PpDiagramElement.count }, -2 do
      assert_difference -> { PpDiagramFlow.count }, -1 do
        @diagram.destroy
      end
    end
  end
end
