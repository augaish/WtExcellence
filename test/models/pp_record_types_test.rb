require "test_helper"

# Both DoA tiers, SLAs and the glossary are governed documents, so they are
# record types rather than a separate register.
class PpRecordTypesTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Types Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @process = @company.pp_processes.create!(name_en: "Procurement", level: 1)
  end

  test "the new governed types are available and named in both locales" do
    %w[executive_doa operational_doa sla glossary].each do |type|
      assert_includes PpRecord::TYPES, type

      I18n.available_locales.each do |locale|
        assert_predicate I18n.t("pp_records.types.#{type}", locale: locale), :present?
        assert_predicate I18n.t("pp_records.types_plural.#{type}", locale: locale), :present?
      end
    end
  end

  test "an executive matrix stands alone but an operational one needs its process" do
    executive = @company.pp_records.new(record_type: "executive_doa", title_en: "Executive DoA")
    assert_predicate executive, :valid?

    operational = @company.pp_records.new(record_type: "operational_doa", title_en: "Procurement DoA")
    assert_not operational.valid?, "an operational matrix must hang off a procedure"

    operational.pp_process = @process
    assert_predicate operational, :valid?
  end

  test "both tiers are recognised as authority matrices" do
    PpRecord::DOA_TYPES.each do |type|
      record = @company.pp_records.new(record_type: type, title_en: "Matrix", pp_process: @process)
      assert_predicate record, :doa?
    end

    assert_not @company.pp_records.new(record_type: "policy", title_en: "Policy").doa?
  end
end
