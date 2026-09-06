# Scores how well-formed a process diagram is, names its maturity level, and
# returns a ranked list of concrete fixes.
#
# This is a faithful port of the reference implementation: the weights, the
# thresholds and the arithmetic are unchanged. Only the surface is idiomatic
# Ruby, and the labels go through i18n so the output is bilingual.
#
# It is a pure function over the diagram's data — no rendering, no HTTP — so it
# is cheap to call and easy to test. The shape it returns (weighted axes ->
# overall score -> maturity tier -> prioritised recommendations) is intentionally
# generic, so a later pass can add other evaluation kinds as additional axis
# sets without changing what callers see.
class ProcessEvaluationService
  TASK_TYPES = PpDiagramElement::TASK_TYPES
  DIGITAL_TASK_TYPES = PpDiagramElement::DIGITAL_TASK_TYPES
  DATA_LIKE_TYPES = PpDiagramElement::ARTIFACT_TYPES

  PRIORITIES = %w[high medium low].freeze

  # Public entry point. `model` is PpDiagram#to_contract (or an equivalent hash).
  def self.evaluate(model, summary = {})
    new(model, summary).evaluate
  end

  # Convenience: evaluate a persisted diagram, inheriting its summary fields.
  def self.evaluate_diagram(diagram)
    summary = diagram.effective_summary
    evaluate(diagram.to_contract, trigger: summary[:trigger], inputs: summary[:inputs], outputs: summary[:outputs])
  end

  def initialize(model, summary = {})
    @model = (model || {}).transform_keys(&:to_s)
    @summary = (summary || {}).transform_keys(&:to_s)
  end

  def evaluate
    assessment = assess
    {
      score: assessment[:score],
      maturity: maturity_level(assessment[:score]),
      axes: assessment[:axes],
      recommendations: build_recommendations(assessment)
    }
  end

  private

  def elements
    @elements ||= Array(@model["elements"]).map { |e| (e || {}).transform_keys(&:to_s) }
  end

  def flows
    @flows ||= Array(@model["flows"]).map { |f| (f || {}).transform_keys(&:to_s) }
  end

  # Summary argument first, then the model's own process-level field.
  def summary_value(summary_key, model_key)
    value = @summary[summary_key]
    present?(value) ? value : @model[model_key]
  end

  def clamp(number)
    [ 0, [ 100, number.round ].min ].max
  end

  def present?(value)
    value.to_s.strip != ""
  end

  # --- processMetrics -----------------------------------------------------
  def metrics
    @metrics ||= begin
      internal = elements.reject { |e| e["scope"] == "external" }
      external = elements.select { |e| e["scope"] == "external" }
      tasks = elements.select { |e| TASK_TYPES.include?(e["type"]) }
      gateways = elements.select { |e| e["type"] == "gateway" }
      data_like = elements.select { |e| DATA_LIKE_TYPES.include?(e["type"]) }

      missing_title = elements.count { |e| !present?(e["title"]) }
      missing_performer = elements.count { |e| !present?(e["performer"]) }
      missing_desc = elements.count { |e| !present?(e["desc"]) && !%w[startEvent endEvent].include?(e["type"]) }
      missing_input = tasks.count { |e| !present?(e["input"]) }
      missing_output = tasks.count { |e| !present?(e["output"]) }

      manual_tasks = tasks.count { |e| e["type"] == "manualTask" }
      digital_tasks = tasks.count { |e| DIGITAL_TASK_TYPES.include?(e["type"]) }

      cross_seq = flows.any? do |f|
        f["kind"] == "sequence" && f.dig("from", "pool") != f.dig("to", "pool")
      end
      message_flows = flows.count { |f| f["kind"] == "message" }

      unique_performers = elements.map { |e| e["performer"] }.select { |p| present?(p) }.uniq

      # Handoffs compare each element with the one BEFORE it in author order
      # (as in the reference implementation), so a change of performer between
      # consecutive steps counts as a handoff.
      handoffs = elements.each_cons(2).count { |prev, curr| prev["performer"].to_s != curr["performer"].to_s }

      {
        internal: internal, external: external, tasks: tasks, gateways: gateways, data_like: data_like,
        missing_title: missing_title, missing_performer: missing_performer, missing_desc: missing_desc,
        missing_input: missing_input, missing_output: missing_output,
        manual_tasks: manual_tasks, digital_tasks: digital_tasks,
        cross_seq: cross_seq, message_flows: message_flows,
        unique_performers: unique_performers, handoffs: handoffs
      }
    end
  end

  # --- assessProcess ------------------------------------------------------
  def assess
    @assess ||= begin
      x = metrics
      count = elements.size

      has_start = elements.any? { |e| e["type"] == "startEvent" }
      has_end = elements.any? { |e| e["type"] == "endEvent" }
      # The summary argument wins; otherwise fall back to the process-level
      # fields carried on the model itself (ProcessModel.trigger /
      # inputsSummary / outputsSummary), so evaluating a diagram's contract on
      # its own still sees what the process card already captured.
      has_trigger = present?(summary_value("trigger", "trigger")) || elements.any? { |e| present?(e["trigger"]) }
      has_inputs = present?(summary_value("inputs", "inputsSummary")) || x[:tasks].any? { |e| present?(e["input"]) }
      has_outputs = present?(summary_value("outputs", "outputsSummary")) || x[:tasks].any? { |e| present?(e["output"]) }

      gateway_labeled = x[:gateways].empty? ||
        x[:gateways].all? { |g| present?(g["flowLabel"]) || present?(g["desc"]) }
      external_ok = x[:external].empty? || (x[:message_flows].positive? && !x[:cross_seq])

      title_completeness = (count - x[:missing_title]).to_f / [ 1, count ].max * 100
      performer_completeness = (count - x[:missing_performer]).to_f / [ 1, count ].max * 100
      io_completeness = (x[:tasks].size * 2 - x[:missing_input] - x[:missing_output]).to_f /
        [ 1, x[:tasks].size * 2 ].max * 100
      description_completeness = (count - x[:missing_desc]).to_f / [ 1, count ].max * 100

      digital_ratio = x[:tasks].empty? ? 0.0 : x[:digital_tasks].to_f / x[:tasks].size
      handoff_pressure = count.zero? ? 0.0 : x[:handoffs].to_f / [ 1, count - 1 ].max

      axes = [
        {
          id: "bpmn", name: I18n.t("evaluation.axes.bpmn.name"),
          score: clamp((has_start ? 18 : 0) + (has_end ? 18 : 0) + (x[:cross_seq] ? 0 : 18) +
                       (external_ok ? 16 : 6) + (gateway_labeled ? 14 : 6) + title_completeness * 0.16),
          note: I18n.t("evaluation.axes.bpmn.note")
        },
        {
          id: "sipoc", name: I18n.t("evaluation.axes.sipoc.name"),
          score: clamp((has_inputs ? 22 : 0) + (has_outputs ? 22 : 0) + (has_trigger ? 16 : 0) +
                       performer_completeness * 0.18 + io_completeness * 0.22),
          note: I18n.t("evaluation.axes.sipoc.note")
        },
        {
          id: "lean", name: I18n.t("evaluation.axes.lean.name"),
          score: clamp(100 - handoff_pressure * 30 -
                       (x[:manual_tasks].to_f / [ 1, x[:tasks].size ].max * 18) +
                       digital_ratio * 18 - (x[:gateways].size > 3 ? 8 : 0)),
          note: I18n.t("evaluation.axes.lean.note")
        },
        {
          id: "iso", name: I18n.t("evaluation.axes.iso.name"),
          score: clamp(description_completeness * 0.28 + io_completeness * 0.30 +
                       performer_completeness * 0.24 + (x[:data_like].any? ? 10 : 3) + (has_outputs ? 8 : 0)),
          note: I18n.t("evaluation.axes.iso.note")
        },
        {
          id: "raci", name: I18n.t("evaluation.axes.raci.name"),
          score: clamp(performer_completeness * 0.55 + (x[:unique_performers].any? ? 25 : 0) +
                       (x[:unique_performers].size <= 8 ? 20 : 10)),
          note: I18n.t("evaluation.axes.raci.note")
        },
        {
          id: "digital", name: I18n.t("evaluation.axes.digital.name"),
          score: clamp(digital_ratio * 55 + (x[:data_like].any? ? 20 : 5) +
                       (x[:message_flows].positive? ? 15 : 5) +
                       (x[:tasks].any? { |e| e["type"] == "businessRuleTask" } ? 10 : 0)),
          note: I18n.t("evaluation.axes.digital.note")
        }
      ]

      weighted = clamp(axes[0][:score] * 0.24 + axes[1][:score] * 0.18 + axes[2][:score] * 0.15 +
                       axes[3][:score] * 0.17 + axes[4][:score] * 0.13 + axes[5][:score] * 0.13)

      {
        axes: axes, score: weighted, metrics: x,
        has_start: has_start, has_end: has_end, has_trigger: has_trigger,
        has_inputs: has_inputs, has_outputs: has_outputs,
        gateway_labeled: gateway_labeled, external_ok: external_ok,
        title_completeness: title_completeness, performer_completeness: performer_completeness,
        io_completeness: io_completeness, description_completeness: description_completeness,
        digital_ratio: digital_ratio, handoff_pressure: handoff_pressure
      }
    end
  end

  # --- maturityLevel ------------------------------------------------------
  def maturity_level(score)
    key =
      if score >= 90 then "excellent"
      elsif score >= 80 then "very_good"
      elsif score >= 70 then "good"
      elsif score >= 55 then "needs_improvement"
      else "weak"
      end

    {
      key: key,
      title: I18n.t("evaluation.maturity.#{key}.title"),
      desc: I18n.t("evaluation.maturity.#{key}.desc"),
      tier: I18n.t("evaluation.maturity.#{key}.tier")
    }
  end

  # --- buildRecommendations -----------------------------------------------
  def build_recommendations(assessment)
    a = assessment
    x = a[:metrics]
    recommendations = []

    add = lambda do |priority, key|
      recommendations << {
        priority: priority,
        title: I18n.t("evaluation.recommendations.#{key}.title"),
        why: I18n.t("evaluation.recommendations.#{key}.why"),
        action: I18n.t("evaluation.recommendations.#{key}.action"),
        method: I18n.t("evaluation.recommendations.#{key}.method")
      }
    end

    add.call("high", "add_start") unless a[:has_start]
    add.call("high", "add_end") unless a[:has_end]
    add.call("high", "separate_external") if x[:cross_seq]
    add.call("high", "add_message_flow") if x[:external].any? && x[:message_flows].zero?
    add.call("medium", "name_trigger") unless a[:has_trigger]
    add.call("medium", "complete_inputs") unless a[:has_inputs]
    add.call("medium", "complete_outputs") unless a[:has_outputs]
    add.call("high", "complete_performers") if x[:missing_performer].positive?
    add.call("medium", "improve_descriptions") if x[:missing_desc].positive?
    add.call("high", "label_gateways") if x[:gateways].any? && !a[:gateway_labeled]
    add.call("medium", "reduce_handoffs") if a[:handoff_pressure] > 0.55
    add.call("low", "raise_automation") if x[:manual_tasks] > x[:digital_tasks] && x[:tasks].size >= 4
    add.call("low", "add_records") if x[:data_like].empty?
    add.call("low", "review_participants") if x[:unique_performers].size > 8
    add.call("low", "maintain_quality") if recommendations.empty?

    recommendations.first(8)
  end
end
