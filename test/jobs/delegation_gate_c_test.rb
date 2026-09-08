require "test_helper"

# Gate C — the delegation cases the reviewer asked to see proven with a
# controllable clock rather than a browser.
class DelegationGateCTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @company = Company.create!(name: "Gate C #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @lender = user("lender")
    @borrower = user("borrower")
    @from = @company.org_units.create!(name_en: "Minister", level: 1, head_user: @lender)
    @to = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @from, head_user: @borrower)
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @authority = @company.authorities.create!(matrix: matrix, name_en: "Sign contracts")
  end

  def user(prefix)
    User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: prefix, is_active: true)
  end

  def delegation(valid_to:, valid_from: Date.current - 30)
    @company.authority_delegations.create!(authority: @authority, from_org_unit: @from, to_org_unit: @to,
      kind: "temporary", status: "active", valid_from: valid_from, valid_to: valid_to)
  end

  def run_job
    DelegationExpiryNoticeJob.new.perform
  end

  test "ended yesterday: authority is denied today; a decision taken while valid keeps its basis" do
    travel_to Time.zone.local(2026, 9, 8, 10, 0) do
      record = delegation(valid_to: Date.current - 1)
      assert_not record.in_force?
      assert record.in_force?(Date.current - 1), "yesterday's decision was made under a valid delegation"
    end
  end

  test "ends today: authority remains valid through the end of the day" do
    travel_to Time.zone.local(2026, 9, 8, 23, 30) do
      record = delegation(valid_to: Date.current)
      assert record.in_force?
      assert_not record.in_force?(Date.current + 1)
    end
  end

  test "31, 30 and 29 days remaining: warning only inside the window" do
    travel_to Time.zone.local(2026, 9, 8, 6, 0) do
      outside = delegation(valid_to: Date.current + 31)
      edge = delegation(valid_to: Date.current + 30)
      inside = delegation(valid_to: Date.current + 29)

      run_job

      assert_nil outside.reload.expiry_notified_at, "31 days out is not yet warned"
      assert_equal "delivered", edge.reload.expiry_notice_outcome
      assert_equal "delivered", inside.reload.expiry_notice_outcome
    end
  end

  test "a record created late, already inside the window, is warned on the next run" do
    travel_to Time.zone.local(2026, 9, 8, 6, 0) do
      record = delegation(valid_to: Date.current + 3)
      run_job
      assert_equal "delivered", record.reload.expiry_notice_outcome
    end
  end

  test "two different heads each receive the notice" do
    delegation(valid_to: Date.current + 5)
    assert_difference("Notification.count", 2) { run_job }
    assert_equal [ @borrower, @lender ].map(&:id).sort, Notification.where(kind: "delegation_expiring").pluck(:recipient_id).sort
  end

  test "one person heading both units receives one notice, not two" do
    @to.update!(head_user: @lender)
    delegation(valid_to: Date.current + 5)
    assert_difference("Notification.count", 1) { run_job }
  end

  test "no heads: examined once, recorded as such, not scanned every run" do
    @from.update!(head_user: nil); @to.update!(head_user: nil)
    record = delegation(valid_to: Date.current + 5)

    assert_no_difference("Notification.count") do
      run_job
      run_job
    end
    assert_equal "no_recipients", record.reload.expiry_notice_outcome, "the stamp records the outcome, not a delivery"
  end

  test "a head assigned after a headless attempt is told on the next run" do
    @from.update!(head_user: nil); @to.update!(head_user: nil)
    record = delegation(valid_to: Date.current + 5)
    run_job
    assert_equal "no_recipients", record.reload.expiry_notice_outcome

    @to.update!(head_user: @borrower)
    assert_difference("Notification.count", 1) { run_job }
    assert_equal "delivered", record.reload.expiry_notice_outcome
  end

  test "a rerun does not duplicate a delivered notice" do
    delegation(valid_to: Date.current + 5)
    run_job
    assert_no_difference("Notification.count") { run_job }
  end

  test "revocation before the run means no reminder" do
    record = delegation(valid_to: Date.current + 5)
    record.update!(status: "revoked", revocation_reason: "Replaced.")
    assert_no_difference("Notification.count") { run_job }
  end

  test "a published matrix version cannot be edited; the next version can" do
    matrix = @authority.matrix
    band = @authority.bands.sole
    band.assignments.create!(level: "authorize", org_unit: @from)

    matrix.update!(current_stage: "s5_published")
    assert_predicate matrix, :completed?

    assert_not @authority.reload.update(name_en: "Changed after publication")
    assert_includes @authority.errors[:base], I18n.t("doa.errors.matrix_published")
    assert_not band.reload.update(max_amount: 5)
    assert_not band.assignments.new(level: "review", org_unit: @to).valid?

    successor = AuthorityMatrixVersionService.open_next(matrix.reload)
    assert successor.authorities.first.update(name_en: "Changed in the next version")
  end

  test "delegating above the grantor's own limit is refused" do
    @authority.bands.sole.update!(max_amount: 1_000)
    @authority.bands.sole.assignments.create!(level: "authorize", org_unit: @from)
    record = @company.authority_delegations.new(authority: @authority, from_org_unit: @from, to_org_unit: @to,
      kind: "permanent", status: "active", limit_amount: 5_000)

    assert_not record.valid?
    assert_predicate record.errors[:limit_amount], :present?
  end
end
