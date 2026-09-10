require "test_helper"

class GovernanceCapaServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "GCS Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @user = User.create!(
      email: "gcs.#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123",
      name: "GCS User", is_active: true
    )
  end

  test "raises a linked high-priority CAPA from a high risk" do
    risk = Risk.create!(company: @company, title: "Ransomware exposure", likelihood: 5, impact: 5)

    capa = GovernanceCapaService.create_from(origin: risk, company: @company, user: @user)

    assert capa.persisted?
    assert_equal risk, capa.origin
    assert_equal "Risk Management", capa.source
    assert_equal "high", capa.priority
    assert_equal @company.id, capa.company_id
    assert_includes risk.reload.linked_capas, capa
  end

  test "raises a linked CAPA from a vendor with priority from risk level" do
    vendor = Vendor.create!(company: @company, name: "Acme Cloud", risk_level: "critical", rating_override_reason: "Outage last quarter")

    capa = GovernanceCapaService.create_from(origin: vendor, company: @company, user: @user)

    assert_equal "Vendor Assessment", capa.source
    assert_equal "high", capa.priority
    assert_equal vendor, capa.origin
  end

  test "raises a linked CAPA from a commitment" do
    commitment = CustomerCommitment.create!(company: @company, title: "Quarterly SLA report", customer_name: "Globex")

    capa = GovernanceCapaService.create_from(origin: commitment, company: @company, user: @user)

    assert_equal "Customer Commitment", capa.source
    assert_equal commitment, capa.origin
    assert_includes commitment.reload.linked_capas, capa
  end

  test "rejects an unsupported origin" do
    assert_raises(GovernanceCapaService::UnsupportedOriginError) do
      GovernanceCapaService.create_from(origin: @company, company: @company, user: @user)
    end
  end
end
