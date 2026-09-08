require "test_helper"

# F25 — the manual omitted the newer modules and described a top-bar search that
# does not exist.
class HelpTopicsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Help Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @user = User.create!(email: "help-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Help Reader", is_active: true)
    CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_admin])
  end

  test "every topic has a partial and a title in both languages" do
    HelpController::TOPICS.each do |slug|
      assert File.exist?(Rails.root.join("app/views/help/topics/_#{slug}.html.erb")),
        "#{slug} has no partial"

      I18n.available_locales.each do |locale|
        assert_predicate I18n.t("help.topics.#{slug}.title", locale: locale, default: ""), :present?,
          "#{slug} has no #{locale} title"
        assert_predicate I18n.t("help.topics.#{slug}.summary", locale: locale, default: ""), :present?,
          "#{slug} has no #{locale} summary"
      end
    end
  end

  test "the manual covers the modules that exist" do
    assert_includes HelpController::TOPICS, "org_and_processes"
    assert_includes HelpController::TOPICS, "policies_procedures"
    assert_includes HelpController::TOPICS, "delegation_of_authority"
  end

  test "every topic page renders in both languages" do
    sign_in @user

    HelpController::TOPICS.each do |slug|
      %w[en ar].each do |locale|
        get help_topic_path(slug: slug, locale: locale)
        assert_response :success, "#{slug} failed to render in #{locale}"
      end
    end
  end

  test "the manual no longer describes a search that does not exist" do
    sign_in @user
    get help_topic_path(slug: "getting_started")

    assert_response :success
    assert_no_match(/top bar holds search/i, response.body)
  end

  test "the index lists every topic" do
    sign_in @user
    get help_path

    assert_response :success
    HelpController::TOPICS.each do |slug|
      assert_select "a[href=?]", help_topic_path(slug: slug)
    end
  end
end
