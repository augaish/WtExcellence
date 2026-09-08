require "test_helper"

class GlossaryAndReferencesTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Glossary Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @other_company = Company.create!(name: "Other Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Governance Policy")
    @term = @company.glossary_terms.create!(term_en: "Structured data", term_ar: "البيانات المنظمة",
      definition_en: "Data formatted into a predefined model before it is stored.",
      definition_ar: "البيانات التي تم تنسيقها وهيكلتها إلى نموذج بيانات محدد مسبقا قبل حفظها")

    standard = Standard.create!(code: "STD-#{SecureRandom.hex(4)}", is_primary: true)
    version = standard.standard_versions.create!(version_label: "1.0", status: "published")
    @clause = version.clauses.create!(code: "7.5.3", sort_order: 1)
  end

  test "a term needs a name in at least one language" do
    blank = @company.glossary_terms.new(definition_en: "Something")

    assert_not blank.valid?
    assert_predicate blank.errors[:base], :present?
  end

  test "a term falls back to the other language when one is missing" do
    english_only = @company.glossary_terms.create!(term_en: "Data Owner")

    assert_equal "Data Owner", english_only.display_term(:ar)
    assert_equal "البيانات المنظمة", @term.display_term(:ar)
  end

  test "a document prints terms selected from the company's own bank" do
    @record.record_terms.create!(glossary_term: @term)

    assert_equal [ @term ], @record.reload.glossary_terms.to_a
  end

  test "a document cannot print another company's definitions" do
    foreign = @other_company.glossary_terms.create!(term_en: "Foreign term")
    link = @record.record_terms.new(glossary_term: foreign)

    assert_not link.valid?
    assert_predicate link.errors[:glossary_term], :present?
  end

  test "the same term is not printed twice in one document" do
    @record.record_terms.create!(glossary_term: @term)
    duplicate = @record.record_terms.new(glossary_term: @term)

    assert_not duplicate.valid?
  end

  test "a reference must name something" do
    empty = @record.references.new

    assert_not empty.valid?
    assert_predicate empty.errors[:name], :present?
  end

  test "a free-text reference keeps the text it was given" do
    reference = @record.references.create!(name: "National Data Management Standards",
      source: "Saudi Data & AI Authority")

    assert_equal "National Data Management Standards", reference.display_name
    assert_equal "Saudi Data & AI Authority", reference.display_source
  end

  test "a clause-linked reference reads its name from the clause" do
    clause = @clause
    reference = @record.references.create!(clause: clause, name: "Typed name that should lose")

    assert_includes reference.display_name, clause.full_code
    assert_not_equal "Typed name that should lose", reference.display_name
  end

  test "references to clauses can be listed on their own" do
    @record.references.create!(name: "External regulation")
    linked = @record.references.create!(clause: @clause)

    assert_equal [ linked ], @record.references.to_clauses.to_a
  end
end
