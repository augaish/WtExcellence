require "test_helper"

# A temporary delegation stops conferring authority the day after it ends, which
# is correct but silent. This warns first.
class DelegationExpiryNoticeJobTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Notice Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @lender = user_named("lender")
    @borrower = user_named("borrower")

    @from = @company.org_units.create!(name_en: "Minister", level: 1, head_user: @lender)
    @to = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @from, head_user: @borrower)

    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @authority = @company.authorities.create!(matrix: matrix, name_en: "Sign contracts")
  end

  def user_named(prefix)
    User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix, is_active: true)
  end

  def delegation(valid_to:, status: "active")
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @from,
      to_org_unit: @to, kind: "temporary", status: status,
      valid_from: Date.current - 1, valid_to: valid_to)
  end

  test "both sides of a delegation nearing expiry are told" do
    record = delegation(valid_to: Date.current + 5)

    assert_difference "Notification.count", 2 do
      DelegationExpiryNoticeJob.new.perform
    end

    recipients = Notification.where(kind: "delegation_expiring").map(&:recipient)
    assert_equal [ @lender, @borrower ].sort_by(&:id), recipients.sort_by(&:id)
    assert_not_nil record.reload.expiry_notified_at
  end

  test "a delegation is warned about once, not on every run" do
    delegation(valid_to: Date.current + 5)
    DelegationExpiryNoticeJob.new.perform

    assert_no_difference "Notification.count" do
      DelegationExpiryNoticeJob.new.perform
    end
  end

  test "a delegation ending beyond the warning window is left alone" do
    delegation(valid_to: Date.current + AuthorityDelegation::EXPIRY_LEAD_DAYS + 10)

    assert_no_difference "Notification.count" do
      DelegationExpiryNoticeJob.new.perform
    end
  end

  test "a revoked delegation is not warned about" do
    record = delegation(valid_to: Date.current + 5)
    record.update!(status: "revoked", revocation_reason: "Superseded.")

    assert_no_difference "Notification.count" do
      DelegationExpiryNoticeJob.new.perform
    end
  end

  test "a permanent delegation has nothing to expire" do
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @from,
      to_org_unit: @to, kind: "permanent", status: "active")

    assert_no_difference "Notification.count" do
      DelegationExpiryNoticeJob.new.perform
    end
  end

  test "a delegation nobody can be told about is not retried forever" do
    @from.update!(head_user: nil)
    @to.update!(head_user: nil)
    record = delegation(valid_to: Date.current + 5)

    assert_no_difference "Notification.count" do
      DelegationExpiryNoticeJob.new.perform
    end
    assert_not_nil record.reload.expiry_notified_at,
      "without the stamp this delegation would be re-examined on every run for the rest of its life"
  end

  test "the notice says which authority, to whom, and when it ends" do
    record = delegation(valid_to: Date.current + 5)
    DelegationExpiryNoticeJob.new.perform

    notification = Notification.where(kind: "delegation_expiring").first
    assert_includes notification.body, "Sign contracts"
    assert_includes notification.body, "Deputy"
    assert_equal record, notification.source
  end
end
