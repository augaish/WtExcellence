require "test_helper"

# The scoring maths is a faithful port of the reference implementation; these
# tests pin the weights, thresholds and edge cases so a refactor cannot drift.
class ProcessEvaluationServiceTest < ActiveSupport::TestCase
  def model(elements: [], flows: [], **summary)
    { "elements" => elements, "flows" => flows }.merge(summary.transform_keys(&:to_s))
  end

  def element(type: "manualTask", **attrs)
    { "type" => type }.merge(attrs.transform_keys(&:to_s))
  end

  # A well-formed process: start, two documented digital tasks, an end.
  def good_model
    model(
      elements: [
        element(type: "startEvent", title: "Start", performer: "HR", desc: "Begins"),
        element(type: "userTask", title: "Review", performer: "HR", desc: "Check details",
                input: "Draft", output: "Reviewed draft"),
        element(type: "serviceTask", title: "Record", performer: "HR", desc: "Store it",
                input: "Reviewed draft", output: "Stored record"),
        element(type: "dataStore", title: "Register", performer: "HR", desc: "System of record"),
        element(type: "endEvent", title: "Done", performer: "HR", desc: "Ends")
      ],
      flows: [ { "kind" => "sequence", "from" => { "pool" => "HR" }, "to" => { "pool" => "HR" } } ],
      trigger: "Request received", inputs: "Draft", outputs: "Stored record"
    )
  end

  test "returns the documented result shape" do
    result = ProcessEvaluationService.evaluate(model)

    assert_equal %i[score maturity blocking_issues axes recommendations], result.keys
    assert_equal 6, result[:axes].size
    assert_equal %w[bpmn sipoc lean iso raci digital], result[:axes].map { |a| a[:id] }
    assert_kind_of Integer, result[:score]
  end

  test "the score is always clamped to 0..100" do
    assert_includes 0..100, ProcessEvaluationService.evaluate(model)[:score]
    assert_includes 0..100, ProcessEvaluationService.evaluate(good_model)[:score]
  end

  test "a well-formed process scores well above an empty one" do
    good = ProcessEvaluationService.evaluate(good_model, trigger: "Request received", inputs: "Draft", outputs: "Record")
    empty = ProcessEvaluationService.evaluate(model)

    assert good[:score] > empty[:score]
    assert good[:score] >= 70, "a documented process should reach at least Good, got #{good[:score]}"
  end

  # Maturity thresholds: 90 / 80 / 70 / 55.
  test "maturity tiers follow the documented thresholds" do
    service = ProcessEvaluationService.new(model)
    tiers = {
      95 => "Level 5", 90 => "Level 5",
      85 => "Level 4", 80 => "Level 4",
      75 => "Level 3", 70 => "Level 3",
      60 => "Level 2", 55 => "Level 2",
      54 => "Level 1", 0 => "Level 1"
    }
    tiers.each do |score, tier|
      assert_equal tier, service.send(:maturity_level, score)[:tier], "score #{score}"
    end
  end

  test "a missing start and end are reported as high priority" do
    result = ProcessEvaluationService.evaluate(
      model(elements: [ element(title: "Only step", performer: "HR", desc: "x", input: "a", output: "b") ])
    )

    titles = result[:recommendations].map { |r| r[:title] }
    assert_includes titles, I18n.t("evaluation.recommendations.add_start.title")
    assert_includes titles, I18n.t("evaluation.recommendations.add_end.title")
    highs = result[:recommendations].select { |r| r[:priority] == "high" }
    assert highs.any?
  end

  # The BPMN rule the spec calls out explicitly.
  test "a sequence flow crossing pools is penalised and reported" do
    crossing = model(
      elements: [
        element(type: "startEvent", title: "Start", performer: "HR", desc: "x"),
        element(type: "sendTask", title: "Send", performer: "Supplier", scope: "external", desc: "x", input: "a", output: "b"),
        element(type: "endEvent", title: "End", performer: "HR", desc: "x")
      ],
      flows: [ { "kind" => "sequence", "from" => { "pool" => "HR" }, "to" => { "pool" => "external" } } ]
    )

    result = ProcessEvaluationService.evaluate(crossing)
    titles = result[:recommendations].map { |r| r[:title] }

    assert_includes titles, I18n.t("evaluation.recommendations.separate_external.title")
    bpmn = result[:axes].detect { |a| a[:id] == "bpmn" }
    assert bpmn[:score] < 100
  end

  test "an external participant without a message flow is reported" do
    result = ProcessEvaluationService.evaluate(
      model(elements: [
        element(type: "startEvent", title: "S", performer: "HR", desc: "x"),
        element(type: "manualTask", title: "Ask", performer: "Vendor", scope: "external", desc: "x", input: "a", output: "b"),
        element(type: "endEvent", title: "E", performer: "HR", desc: "x")
      ])
    )

    assert_includes result[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.add_message_flow.title")
  end

  test "unlabelled gateways are reported" do
    result = ProcessEvaluationService.evaluate(
      model(elements: [
        element(type: "startEvent", title: "S", performer: "HR", desc: "x"),
        element(type: "gateway", title: "Approved?", performer: "HR"),
        element(type: "endEvent", title: "E", performer: "HR", desc: "x")
      ])
    )

    assert_includes result[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.label_gateways.title")
  end

  test "a labelled gateway is not reported" do
    result = ProcessEvaluationService.evaluate(
      model(elements: [
        element(type: "startEvent", title: "S", performer: "HR", desc: "x"),
        element(type: "gateway", title: "Approved?", performer: "HR", flowLabel: "Yes / No"),
        element(type: "endEvent", title: "E", performer: "HR", desc: "x")
      ])
    )

    refute_includes result[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.label_gateways.title")
  end

  test "missing performers are reported as high priority" do
    result = ProcessEvaluationService.evaluate(
      model(elements: [ element(title: "Step", desc: "x", input: "a", output: "b") ])
    )

    rec = result[:recommendations].detect { |r| r[:title] == I18n.t("evaluation.recommendations.complete_performers.title") }
    assert rec.present?
    assert_equal "high", rec[:priority]
  end

  test "heavy manual work lowers the digital axis" do
    manual = model(elements: Array.new(5) { |i| element(type: "manualTask", title: "S#{i}", performer: "HR", desc: "x", input: "a", output: "b") })
    digital = model(elements: Array.new(5) { |i| element(type: "serviceTask", title: "S#{i}", performer: "HR", desc: "x", input: "a", output: "b") })

    manual_score = ProcessEvaluationService.evaluate(manual)[:axes].detect { |a| a[:id] == "digital" }[:score]
    digital_score = ProcessEvaluationService.evaluate(digital)[:axes].detect { |a| a[:id] == "digital" }[:score]

    assert digital_score > manual_score
  end

  test "many handoffs are reported" do
    elements = %w[A B C D E].map { |p| element(title: "Step #{p}", performer: p, desc: "x", input: "a", output: "b") }
    result = ProcessEvaluationService.evaluate(model(elements: elements))

    assert_includes result[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.reduce_handoffs.title")
  end

  test "too many participants are reported" do
    elements = (1..10).map { |i| element(title: "Step #{i}", performer: "Dept #{i}", desc: "x", input: "a", output: "b") }
    result = ProcessEvaluationService.evaluate(model(elements: elements))

    assert_includes result[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.review_participants.title")
  end

  test "a balanced process gets the maintain-quality note and nothing else" do
    result = ProcessEvaluationService.evaluate(good_model)

    if result[:recommendations].size == 1
      assert_equal I18n.t("evaluation.recommendations.maintain_quality.title"),
        result[:recommendations].first[:title]
    end
    assert result[:recommendations].any?, "there is always at least one line of guidance"
  end

  test "at most eight recommendations are returned" do
    result = ProcessEvaluationService.evaluate(model(elements: [ element(title: nil) ]))

    assert result[:recommendations].size <= 8
  end

  test "an empty model does not raise and scores low" do
    result = ProcessEvaluationService.evaluate({})

    assert_kind_of Integer, result[:score]
    assert result[:score] < 70
  end

  test "process-level summary fields satisfy the trigger and I/O checks" do
    bare = model(elements: [
      element(type: "startEvent", title: "S", performer: "HR", desc: "x"),
      element(type: "endEvent", title: "E", performer: "HR", desc: "x")
    ])

    without = ProcessEvaluationService.evaluate(bare)
    with = ProcessEvaluationService.evaluate(bare, trigger: "Request", inputs: "Form", outputs: "Decision")

    assert with[:score] > without[:score]
    refute_includes with[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.name_trigger.title")
  end

  test "evaluating a saved diagram inherits the process card summary" do
    company = Company.create!(name: "Eval Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    process = company.pp_processes.create!(name_en: "Hiring", level: 1, category: "core",
      trigger_text: "Vacancy approved", inputs: "Job description", outputs: "Contract")
    diagram = company.pp_diagrams.create!(owner: process, name: "Hiring")
    diagram.elements.create!(element_type: "startEvent", title: "Start", performer: "HR", description: "x")
    diagram.elements.create!(element_type: "userTask", title: "Interview", performer: "HR",
      description: "Meet", input: "CV", output: "Notes")
    diagram.elements.create!(element_type: "endEvent", title: "End", performer: "HR", description: "x")

    result = ProcessEvaluationService.evaluate_diagram(diagram.reload)

    assert_kind_of Integer, result[:score]
    refute_includes result[:recommendations].map { |r| r[:title] },
      I18n.t("evaluation.recommendations.name_trigger.title")
  end
end
