require "test_helper"

class DocumentClassificationTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Class Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
  end

  test "the four levels run from most to least restrictive" do
    assert_equal %w[top_secret secret internal public], DocumentClassification::KEYS
    assert_operator DocumentClassification.rank("top_secret"), :<, DocumentClassification.rank("public")
  end

  test "every level has a label and its quoted definition in both locales" do
    I18n.available_locales.each do |locale|
      DocumentClassification::KEYS.each do |key|
        assert_predicate DocumentClassification.label(key, locale), :present?, "#{key} has no #{locale} label"
        assert_predicate DocumentClassification.description(key, locale), :present?, "#{key} has no #{locale} description"
      end
    end
  end

  test "only public records may be shown outside the company" do
    assert DocumentClassification.publishable?("public")
    %w[top_secret secret internal].each do |key|
      assert_not DocumentClassification.publishable?(key), "#{key} must not be externally publishable"
    end
  end

  test "a record defaults to internal rather than public" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Unclassified Policy")

    assert_equal "internal", record.classification
    assert_not record.externally_publishable?
  end

  test "a record rejects an unknown classification" do
    record = @company.pp_records.new(record_type: "policy", title_en: "Bad", classification: "cosmic")

    assert_not record.valid?
    assert_includes record.errors[:classification], "is not included in the list"
  end
end
