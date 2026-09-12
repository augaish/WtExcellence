require "test_helper"

class Dashboard::ResendInvitationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Resend Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @super_admin = User.create!(email: "rs-root-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Root", role: "super_admin", is_active: true)
    @invited = User.create!(email: "rs-invited-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Invited", is_active: false,
      invitation_token: User.generate_invitation_token, invitation_sent_at: 10.days.ago, invitation_expires_at: 3.days.ago)
    CompanyUser.create!(company: @company, user: @invited, role: CompanyUser::ROLES[:company_viewer])
  end

  test "a pending invitation is sent again with a fresh link" do
    sign_in @super_admin
    get dashboard_account_management_users_path
    assert_select "form[action=?]", dashboard_resend_invitation_path(@invited)

    old_token = @invited.invitation_token
    assert_enqueued_emails 1 do
      post dashboard_resend_invitation_path(@invited)
    end
    assert_response :see_other
    @invited.reload
    assert_not_equal old_token, @invited.invitation_token
    assert @invited.invitation_valid?
    assert AuditLog.exists?(entity_id: @invited.id, action: "RESEND_USER_INVITATION")
  end

  test "an accepted user has nothing to resend" do
    @invited.update!(invitation_accepted_at: Time.current, is_active: true)
    sign_in @super_admin
    assert_no_enqueued_emails { post dashboard_resend_invitation_path(@invited) }
  end
end
