# Assembles everything a governed document prints, in the order the source
# templates print it.
#
# The rule this service exists to enforce: **a document is a pure function of
# record data**. Nothing is authored here that a user cannot see and correct on
# the record itself, so "publish with the client's logo" stays a button rather
# than a project. Anything the templates contain that is not derivable is
# either boilerplate (the classification definitions) or a field we are missing.
#
# It returns a structured document rather than markup, so a second renderer —
# DOCX — becomes another consumer of the same sections instead of a rewrite.
class RecordDocument
  Section = Struct.new(:key, :title, :kind, :payload, keyword_init: true) do
    def empty?
      payload.blank?
    end
  end

  # Types that document how work is carried out print the process card, its
  # diagram, its steps and its authority matrix. The rest do not have a process.
  PROCESS_SECTION_TYPES = %w[procedure work_instruction form operational_doa].freeze

  def initialize(record, locale: I18n.locale)
    @record = record
    @locale = locale
  end

  attr_reader :record, :locale

  def company
    record.company
  end

  # The cover page: owner, dates, version, classification, and the company's own
  # branding.
  def cover
    {
      title: record.display_title(locale),
      type_label: record.type_label(locale),
      code: record.code,
      version: record.version_label.presence || "v#{record.version_number}",
      owner: record.owner_org_unit&.display_name(locale) || record.owner_user&.name,
      effective_date: record.effective_date,
      review_date: record.review_date,
      classification: record.classification_label(locale),
      company_name: company&.name,
      palette: company&.brand_palette
    }
  end

  # Only the sections that have something to print, so a document never shows an
  # empty heading.
  def sections
    all_sections.reject(&:empty?)
  end

  private

  def all_sections
    [
      definitions_section,
      body_section,
      process_card_section,
      diagram_section,
      steps_section,
      authority_matrix_section,
      service_levels_section,
      references_section,
      classification_section,
      change_log_section,
      approvals_section
    ].compact
  end

  # التعريفات والاختصارات
  def definitions_section
    terms = record.glossary_terms.map do |term|
      {
        term: term.display_term(locale),
        abbreviation: term.abbreviation,
        definition: term.display_definition(locale)
      }
    end

    section("definitions", :table, terms)
  end

  def body_section
    section("body", :prose, record.description)
  end

  # بطاقة الإجراء — every field the procedure template asks for, all of which the
  # process already carries.
  def process_card_section
    process = record.pp_process
    return nil if process.nil? || !PROCESS_SECTION_TYPES.include?(record.record_type)

    fields = {
      "objective" => process.objective,
      "owner" => process.owner_org_unit&.display_name(locale),
      "trigger" => process.trigger_text,
      "inputs" => process.inputs,
      "outputs" => process.outputs,
      "predecessor" => process.predecessor_process&.display_name(locale),
      "successor" => process.successor_process&.display_name(locale),
      "frequency" => enum_label("process_architecture.frequencies", process.frequency),
      "total_time" => total_time_for(process),
      "automation_status" => enum_label("process_architecture.automation", process.automation_status),
      "related_policies" => process.related_policies,
      "technical_systems" => process.technical_systems,
      "forms_used" => process.forms_used,
      "kpis" => process.kpis
    }.compact_blank

    section("process_card", :fields, fields)
  end

  # The total the steps add up to wins over any typed value: the document must
  # not quote a duration the procedure's own steps contradict.
  def total_time_for(process)
    unit = process.total_time_unit.presence || "hours"
    computed = process.computed_total_in(unit)
    return "#{trim_number(computed)} #{unit_label(unit)}" if computed

    return nil if process.total_time_value.blank?

    "#{trim_number(process.total_time_value)} #{unit_label(process.total_time_unit)}"
  end

  # 24 rather than 24.0; 1.5 stays 1.5.
  def trim_number(value)
    number = value.to_f
    (number % 1).zero? ? number.to_i.to_s : number.to_s
  end

  # An internal value never reaches the page: on_demand prints as "On demand".
  def enum_label(namespace, value)
    return nil if value.blank?

    I18n.t("#{namespace}.#{value}", locale: locale, default: value.to_s.humanize)
  end

  def unit_label(unit)
    return "" if unit.blank?

    I18n.t("process_steps.units.#{unit}", locale: locale, default: unit)
  end

  # مخطط الإجراء — rendered server-side, so the document carries the same diagram
  # the app shows.
  def diagram_section
    diagram = record.pp_process&.diagrams&.first || record.diagrams.first
    return nil if diagram.nil?

    section("diagram", :diagram, diagram)
  end

  # خطوات الإجراء
  def steps_section
    process = record.pp_process
    return nil if process.nil?

    rows = process.steps.map do |step|
      {
        position: step.position,
        activity: step.activity,
        description: step.description,
        responsible: step.responsible_label(locale),
        duration: step_duration(step),
        system: step.system_used
      }
    end

    section("steps", :table, rows)
  end

  def step_duration(step)
    return nil if step.duration_value.blank?

    "#{step.duration_value} #{unit_label(step.duration_unit)}"
  end

  # مصفوفة الصلاحيات الإجرائية, with the conditions rendered as footnotes rather
  # than lost.
  def authority_matrix_section
    process = record.pp_process
    return nil if process.nil?

    rows = process.authorities.map do |authority|
      {
        item: authority.item,
        decision: authority.decision,
        assignments: AuthorityLevel::KEYS.index_with do |level|
          authority.assignments.select { |a| a.level == level }
                   .map { |a| { holder: a.holder_label(locale), condition: a.condition } }
        end
      }
    end

    section("authority_matrix", :matrix, rows)
  end

  # The measurable commitments of an agreement. Printed only for records that
  # have them, so a policy never shows an empty service level table.
  def service_levels_section
    rows = record.service_levels.map do |level|
      {
        service: level.service_name,
        metric: level.metric_label(locale),
        target: level.target_label(locale),
        measurement: level.measurement_method,
        coverage: level.coverage
      }
    end

    section("service_levels", :table, rows)
  end

  # المراجع
  def references_section
    rows = record.references.map do |reference|
      { name: reference.display_name(locale), source: reference.display_source(locale) }
    end

    section("references", :table, rows)
  end

  # تصنيف الوثيقة — the four definitions, quoted. This is the one section that is
  # boilerplate rather than record data.
  def classification_section
    rows = DocumentClassification::KEYS.map do |key|
      {
        label: DocumentClassification.label(key, locale),
        definition: DocumentClassification.description(key, locale),
        current: key == record.classification
      }
    end

    section("classification", :table, rows)
  end

  # سجل التغييرات — built from the version chain, not typed into a table.
  def change_log_section
    rows = version_chain.map do |version|
      {
        version: version.version_label.presence || "v#{version.version_number}",
        date: version.effective_date || version.created_at.to_date,
        prepared_by: version.owner_user&.name,
        # A change log records what changed, which the record's description
        # does not say. The first version has nothing to change from.
        description: version.change_summary.presence ||
          (version.previous_version_id.nil? ? I18n.t("record_document.initial_version", locale: locale) : nil)
      }
    end

    section("change_log", :table, rows)
  end

  # Oldest first, so the log reads the way a change log reads.
  def version_chain
    chain = []
    current = record
    while current
      chain.unshift(current)
      current = current.previous_version
      break if chain.size > 50
    end
    chain
  end

  # المراجعات والاعتمادات — the signatures already captured by the lifecycle,
  # rather than a table filled in by hand after the fact.
  def approvals_section
    rows = record.stage_approvals.includes(:org_unit, :received_by).map do |approval|
      {
        role: AuthorityLevel.label(PpStage.level_of(approval.stage_key), locale),
        unit: approval.org_unit.display_name(locale),
        name: approval.received_by&.name,
        date: approval.received_at&.to_date,
        received: approval.received?
      }
    end

    section("approvals", :table, rows)
  end

  def section(key, kind, payload)
    Section.new(
      key: key,
      title: I18n.t("record_document.sections.#{key}", locale: locale),
      kind: kind,
      payload: payload
    )
  end
end
