require "test_helper"

class VendorTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Vendor Test Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )
  end

  test "requires name" do
    vendor = Vendor.new(company: @company)

    refute vendor.valid?
    assert_includes vendor.errors[:name], "can't be blank"
  end

  test "defaults to unassessed risk level" do
    vendor = Vendor.create!(company: @company, name: "Cloud Host Inc")

    assert_equal "unassessed", vendor.risk_level
  end

  test "soft_delete! excludes vendor from active scope" do
    vendor = Vendor.create!(company: @company, name: "Cloud Host Inc")

    vendor.soft_delete!

    assert vendor.deleted?
    refute_includes Vendor.active.where(company: @company), vendor
  end
end
