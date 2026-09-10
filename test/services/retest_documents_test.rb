require "test_helper"

# R03/R04/R05 — what the record shows, the document must show.
class RetestDocumentsTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Doc2 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
  end

  test "an executive matrix document prints one row per authority with its limit text and holders" do
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    unit = @company.org_units.create!(name_en: "Procurement", level: 1)
    category = @company.authority_categories.create!(name_en: "Contracting")
    authority = @company.authorities.create!(matrix: matrix, name_en: "Approve purchase orders", authority_category: category,
      limit_text: "A: SAR 0-10,000\nB: above 10,000 up to 50,000")
    unlimited = @company.authorities.create!(matrix: matrix, name_en: "Sign NDAs", authority_category: category)
    authority.default_band.assignments.create!(level: "authorize", org_unit: unit)
    authority.default_band.assignments.create!(level: "review", holder_title: "Finance Director", condition: "Above budget line")

    section = RecordDocument.new(matrix.reload).sections.find { |s| s.key == "executive_matrix" }
    assert section, "the principal content of the record was missing from its document"
    assert_equal 2, section.payload.size
    assert_equal "Contracting", section.payload.first[:category]
    assert_equal "A: SAR 0-10,000\nB: above 10,000 up to 50,000", section.payload.first[:band], "the limit is printed exactly as written"
    assert_equal "", section.payload.last[:band], "a blank limit prints blank, never 'all amounts'"
    assert_equal [ { holder: "Procurement", condition: nil } ], section.payload.first[:assignments]["authorize"]
    assert_equal "Above budget line", section.payload.first[:assignments]["review"].first[:condition]
    refute_includes section.payload.map { |r| r[:band] }.join, "All amounts"
    assert_nil unlimited.limit_text
  end

  test "a policy has no executive matrix section" do
    policy = @company.pp_records.create!(record_type: "policy", title_en: "Policy", description: "x")
    assert_not_includes RecordDocument.new(policy).sections.map(&:key), "executive_matrix"
  end

  test "the SLA document keeps the not-measurable status, the other party and the remedy" do
    sla = @company.pp_records.create!(record_type: "sla", title_en: "Support SLA", counterparty: "Finance (internal customer)")
    sla.service_levels.create!(service_name: "Portal", metric: "availability", target_value: 99.9, target_unit: "percent",
      measurement_method: "available minutes / scheduled minutes", remedy: "Service credit 5%")
    sla.service_levels.create!(service_name: "Advisory", metric: "response_time", target_unit: "hours",
      measurement_method: "ticket receipt to reply")
    sla.service_levels.create!(service_name: "Accuracy", metric: "accuracy", target_value: 98, target_unit: "percent")

    document = RecordDocument.new(sla.reload)
    assert_equal "Finance (internal customer)", document.cover[:counterparty]

    rows = document.sections.find { |s| s.key == "service_levels" }.payload
    assert_equal I18n.t("sla.status.measurable"), rows[0][:status]
    assert_equal "Service credit 5%", rows[0][:remedy]
    assert_equal I18n.t("sla.status.target_missing"), rows[1][:status]
    assert_equal I18n.t("sla.status.method_missing"), rows[2][:status]
  end

  test "the Word version carries the executive matrix and the SLA statuses" do
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    authority = @company.authorities.create!(matrix: matrix, name_en: "Approve purchase orders")
    authority.bands.sole.assignments.create!(level: "authorize", holder_title: "Procurement Head")
    bytes = RecordDocxRenderer.new(RecordDocument.new(matrix.reload)).render
    xml = Zip::File.open_buffer(StringIO.new(bytes)).get_entry("word/document.xml").get_input_stream.read.force_encoding("UTF-8")
    assert_includes xml, "Approve purchase orders"
    assert_includes xml, "Procurement Head"

    sla = @company.pp_records.create!(record_type: "sla", title_en: "SLA", counterparty: "Finance")
    sla.service_levels.create!(service_name: "Accuracy", metric: "accuracy", target_value: 98, target_unit: "percent")
    bytes = RecordDocxRenderer.new(RecordDocument.new(sla.reload)).render
    xml = Zip::File.open_buffer(StringIO.new(bytes)).get_entry("word/document.xml").get_input_stream.read.force_encoding("UTF-8")
    assert_includes xml, I18n.t("sla.status.method_missing")
    assert_includes xml, "Finance"
  end
end
