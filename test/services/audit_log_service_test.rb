require "test_helper"

class AuditLogServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Audit Co #{SecureRandom.hex(4)}", license_seats: 5, is_active: true)
    @user = User.create!(email: "audit-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Auditor", is_active: true)
  end

  test "writes an audit log entry" do
    assert_difference -> { AuditLog.count }, 1 do
      AuditLogService.log_action(
        actor_user: @user, company: @company, action: "TEST_ACTION",
        entity_type: "company", entity_id: @company.id
      )
    end
  end

  test "does nothing without an actor" do
    assert_no_difference -> { AuditLog.count } do
      AuditLogService.log_action(actor_user: nil, company: @company, action: "TEST_ACTION")
    end
  end

  test "does nothing when no company can be resolved" do
    assert_no_difference -> { AuditLog.count } do
      AuditLogService.log_action(actor_user: @user, company: nil, action: "TEST_ACTION")
    end
  end

  # Regression: audit logging is best-effort and rescues everything. Without a
  # SAVEPOINT, a failed insert aborts the caller's PostgreSQL transaction, and
  # every later statement dies with InFailedSqlTransaction even though the
  # exception was swallowed. The caller must be able to keep working.
  test "a failed audit insert does not poison the caller's transaction" do
    created = nil

    ActiveRecord::Base.transaction do
      # `action` is limited to 200 characters, so this insert fails at the
      # database level and is swallowed by the service.
      AuditLogService.log_action(
        actor_user: @user, company: @company, action: "X" * 500,
        entity_type: "company", entity_id: @company.id
      )

      # The caller's transaction must still be usable.
      created = Company.create!(name: "After Audit #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    end

    assert created.persisted?, "the caller's transaction was poisoned by a failed audit write"
    assert Company.exists?(created.id)
  end
end
