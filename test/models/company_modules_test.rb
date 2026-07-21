require "test_helper"

class CompanyModulesTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Module Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )
  end

  test "modules default to enabled when no row exists" do
    assert @company.module_enabled?(:capa)
    assert @company.module_enabled?(:risk)
    assert @company.module_enabled?("library")
  end

  test "set_module! disables then re-enables a module" do
    @company.set_module!(:capa, false)
    refute @company.reload.module_enabled?(:capa)

    @company.set_module!(:capa, true)
    assert @company.reload.module_enabled?(:capa)
  end

  test "disabling one module does not affect others" do
    @company.set_module!(:capa, false)

    refute @company.module_enabled?(:capa)
    assert @company.module_enabled?(:standards)
    assert @company.module_enabled?(:risk)
  end

  test "trust_center module is backed by the companies column, not a row" do
    @company.update!(trust_center_enabled: false)
    refute @company.module_enabled?(:trust_center)

    @company.set_module!(:trust_center, true)
    assert @company.reload.trust_center_enabled?
    assert @company.module_enabled?(:trust_center)
    assert_equal 0, @company.company_modules.where(module_key: "trust_center").count
  end

  test "unknown module key reads as enabled and set_module! raises" do
    assert @company.module_enabled?(:does_not_exist)
    assert_raises(ArgumentError) { @company.set_module!(:nope, false) }
  end

  test "CompanyModule rejects an unknown module_key" do
    record = CompanyModule.new(company: @company, module_key: "bogus", enabled: true)
    refute record.valid?
    assert_includes record.errors[:module_key], "is not included in the list"
  end

  test "CompanyModule enforces one row per module per company" do
    @company.set_module!(:capa, false)
    dup = CompanyModule.new(company: @company, module_key: "capa", enabled: true)
    refute dup.valid?
  end
end
