require "test_helper"

class RiskWorkspaceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Risk Workspace Test Co #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true
    )
  end

  test "requires name" do
    workspace = RiskWorkspace.new(company: @company)

    refute workspace.valid?
    assert_includes workspace.errors[:name], "can't be blank"
  end

  test "soft_delete! excludes workspace from active scope" do
    workspace = RiskWorkspace.create!(company: @company, name: "ISO 27001")

    workspace.soft_delete!

    assert workspace.deleted?
    refute_includes RiskWorkspace.active.where(company: @company), workspace
  end

  test "nullifies associated risks on destroy" do
    workspace = RiskWorkspace.create!(company: @company, name: "SOC 2")
    risk = Risk.create!(company: @company, title: "Vendor outage", likelihood: 3, impact: 3, risk_workspace: workspace)

    workspace.destroy

    assert_nil risk.reload.risk_workspace_id
  end
end
