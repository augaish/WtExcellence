require "test_helper"

# The sign-in page is read in the visitor's language before they have an account.
class SignInPageTest < ActionDispatch::IntegrationTest
  test "the sign-in page comes in Arabic with a language link each way" do
    get new_user_session_path
    assert_select "html[lang=en][dir=ltr]"
    assert_select "h2", text: I18n.t("sign_in_page.title", locale: :en)
    assert_select "a[href=?]", switch_language_path(:ar)

    get switch_language_path(:ar), headers: { "HTTP_REFERER" => new_user_session_path }
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select "html[lang=ar][dir=rtl]"
    assert_select "h2", text: I18n.t("sign_in_page.title", locale: :ar)
    assert_select "input[type=submit][value=?]", I18n.t("sign_in_page.submit", locale: :ar)
    assert_select "a[href=?]", switch_language_path(:en)
  end
end

class SignInFollowsHomepageLanguageTest < ActionDispatch::IntegrationTest
  test "the homepage's Sign in link carries its language and the sign-in page opens in it" do
    get "/ar"
    assert_select "a.btn-ghost[href$=?]", "/users/sign_in?locale=ar"
    get "/en"
    assert_select "a.btn-ghost[href$=?]", "/users/sign_in?locale=en"

    get new_user_session_path(locale: :ar)
    assert_select "html[lang=ar][dir=rtl]"
    assert_select "h2", text: I18n.t("sign_in_page.title", locale: :ar)
    get new_user_session_path
    assert_select "html[lang=ar]", 1, "the language sticks for the next page on the app host"
  end
end
