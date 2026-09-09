require "test_helper"

# A document must be a pure function of record data: anything printed has to be
# visible and correctable on the record itself.
class RecordDocumentTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Doc Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @unit = @company.org_units.create!(name_en: "Institutional Excellence", name_ar: "التميز المؤسسي", level: 1)
    @process = @company.pp_processes.create!(name_en: "Policy development", level: 2, category: "core", parent: @company.pp_processes.create!(name_en: "L1 " + "Policy development", level: 1, category: "core"),
      objective: "Govern how policies are written", trigger_text: "A new regulation is issued")
    @record = @company.pp_records.create!(record_type: "procedure", title_en: "Policy Development Procedure",
      title_ar: "إجراء تطوير السياسات", code: "PRO-01", pp_process: @process,
      description: "Govern how policies are written", trigger_text: "A new regulation is issued",
      owner_org_unit: @unit, classification: "internal", version_label: "v1.0")
  end

  def document(locale: :en)
    RecordDocument.new(@record.reload, locale: locale)
  end

  test "the cover carries identity, dates, classification and the company palette" do
    cover = document.cover

    assert_equal "Policy Development Procedure", cover[:title]
    assert_equal "PRO-01", cover[:code]
    assert_equal "Institutional Excellence", cover[:owner]
    assert_equal "Internal (Restricted)", cover[:classification]
    assert_equal BrandPalette::DEFAULT_PRIMARY, cover[:palette].primary
  end

  test "the cover follows the reader's language" do
    assert_equal "إجراء تطوير السياسات", document(locale: :ar).cover[:title]
    assert_equal "التميز المؤسسي", document(locale: :ar).cover[:owner]
  end

  test "sections with nothing to print are left out" do
    keys = document.sections.map(&:key)

    assert_not_includes keys, "definitions"
    assert_not_includes keys, "references"
    assert_includes keys, "classification", "the classification table is boilerplate and always prints"
  end

  test "definitions come from the company glossary" do
    term = @company.glossary_terms.create!(term_en: "Policy", definition_en: "A binding rule.")
    @record.record_terms.create!(glossary_term: term)

    definitions = document.sections.find { |s| s.key == "definitions" }
    assert_equal [ { term: "Policy", abbreviation: nil, definition: "A binding rule." } ], definitions.payload
  end

  test "a clause-linked reference prints the clause, not the typed text" do
    standard = Standard.create!(code: "STD-#{SecureRandom.hex(4)}", is_primary: true)
    version = standard.standard_versions.create!(version_label: "1.0", status: "published")
    clause = version.clauses.create!(code: "7.5.3", sort_order: 1)
    @record.references.create!(clause: clause, name: "Typed text that should lose")

    references = document.sections.find { |s| s.key == "references" }
    assert_includes references.payload.first[:name], "7.5.3"
  end

  test "the procedure card prints the fields the procedure carries" do
    card = document.sections.find { |s| s.key == "process_card" }

    assert_equal "Govern how policies are written", card.payload["objective"]
    assert_equal "A new regulation is issued", card.payload["trigger"]
    assert_not_includes card.payload.keys, "kpis", "blank fields are not printed"
  end

  test "the total time quoted is the one the steps add up to" do
    @record.update!(total_time_value: 99, total_time_unit: "hours")
    @record.steps.create!(position: 1, duration_value: 2, duration_unit: "hours")
    @record.steps.create!(position: 2, duration_value: 3, duration_unit: "hours")

    card = document.sections.find { |s| s.key == "process_card" }
    assert_equal "5 Hours", card.payload["total_time"],
      "a document must not quote a duration its own steps contradict"
  end

  test "steps print in order with their responsible position" do
    @record.steps.create!(position: 2, activity: "Review", responsible_title: "Quality Manager")
    @record.steps.create!(position: 1, activity: "Draft", responsible_title: "Policies Specialist")

    steps = document.sections.find { |s| s.key == "steps" }
    assert_equal [ "Draft", "Review" ], steps.payload.map { |row| row[:activity] }
    assert_equal "Policies Specialist", steps.payload.first[:responsible]
  end

  test "the authority matrix groups holders by level and keeps conditions" do
    authority = @process.authorities.create!(item: "Publication", decision: "Approve publication")
    authority.assignments.create!(level: "authorize", holder_title: "Deputy Minister", condition: "Above SAR 1m")
    authority.assignments.create!(level: "prepare", holder_title: "Policies Specialist")

    matrix = document.sections.find { |s| s.key == "authority_matrix" }
    row = matrix.payload.first

    assert_equal [ { holder: "Deputy Minister", condition: "Above SAR 1m" } ], row[:assignments]["authorize"]
    assert_empty row[:assignments]["inform"]
  end

  test "the classification table marks the level this document carries" do
    table = document.sections.find { |s| s.key == "classification" }
    current = table.payload.select { |row| row[:current] }

    assert_equal 1, current.size
    assert_equal "Internal (Restricted)", current.first[:label]
  end

  test "the change log is built from the version chain, oldest first" do
    first = @company.pp_records.create!(record_type: "procedure", title_en: "First", pp_process: @process,
      version_label: "v0.9", version_number: 1)
    @record.update!(previous_version: first, version_number: 2, change_summary: @record.change_summary.presence || "Revised")

    log = document.sections.find { |s| s.key == "change_log" }
    assert_equal [ "v0.9", "v1.0" ], log.payload.map { |row| row[:version] }
  end

  test "approvals come from the lifecycle rather than a hand-filled table" do
    approver = User.create!(email: "app-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Approver", is_active: true)
    @record.stage_approvals.create!(stage_key: "s4_final", org_unit: @unit,
      requested_at: 2.days.ago, received_at: 1.day.ago, received_by: approver)

    approvals = document.sections.find { |s| s.key == "approvals" }
    row = approvals.payload.sole

    assert_equal "Authorize", row[:role], "the role is the authority level the stage exercises"
    assert_equal "Approver", row[:name]
    assert row[:received]
  end

  test "a policy prints no procedure sections" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Data Policy",
      description: "Policy clauses.")
    keys = RecordDocument.new(policy).sections.map(&:key)

    assert_includes keys, "body"
    assert_not_includes keys, "process_card"
    assert_not_includes keys, "steps"
  end
end
