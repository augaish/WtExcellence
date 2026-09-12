require "test_helper"

# A password reset must never fail because the mail server does: the email
# goes through the queue and the page answers at once.
class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "asking for a reset queues the email instead of sending it in the request" do
    user = User.create!(email: "reset-#{SecureRandom.hex(3)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Reset Me", is_active: true)

    get new_user_password_path
    assert_response :success

    assert_enqueued_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end
    assert_response :see_other
    assert user.reload.reset_password_token.present?

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ user.email ], mail.to
    assert_includes mail.body.encoded, "/users/password/edit?reset_password_token="
  end
end
