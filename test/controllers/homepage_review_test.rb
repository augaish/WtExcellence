require "test_helper"

# Homepage review: stable language URLs with hreflang, a main landmark and
# skip link, the new product section, illustrative tags, and a waitlist page
# that keeps its bearings.
class HomepageReviewTest < ActionDispatch::IntegrationTest
  test "each language has its own URL with canonical, hreflang and share metadata" do
    get "/ar"
    assert_response :success
    assert_select "html[lang=ar][dir=rtl]"
    assert_select "link[rel=canonical][href$='/ar']"
    assert_select "link[rel=alternate][hreflang=en][href$='/en']"
    assert_select "link[rel=alternate][hreflang=ar][href$='/ar']"
    assert_select "meta[property='og:locale'][content=ar_SA]"

    get "/en"
    assert_response :success
    assert_select "html[lang=en][dir=ltr]"
    assert_select "a[hreflang=ar][href$='/ar']"
  end

  test "the page has a main landmark, a skip link, and Prove and Documents in the navigation" do
    get "/en"
    assert_select "main#main"
    assert_select "a.skip-link[href='#main']"
    assert_select "nav.nav-links a[href='#prove']"
    assert_select "nav.nav-links a[href='#documents']"
    assert_select "section#documents h2", text: /Govern how work is done/
  end

  test "sample panels are labelled illustrative and the AI claim matches the product" do
    get "/en"
    assert_select "span.demo-tag", minimum: 3
    assert_select "body", text: /proposed actions that stay drafts/
    refute_match(/all reviewable before you save/, response.body)
  end

  test "the waitlist page links back and switches language" do
    get new_waitlist_path
    assert_response :success
    assert_select "a[href=?]", root_path, text: /Back to homepage/
    assert_select "a[lang=ar]"
  end

  test "the hero is the owner's line, the call to action is a demo, and the footer links the policy pages" do
    get "/en"
    assert_select "h1", text: /Excellence, Risk, Governance/
    assert_select "a.btn-primary", text: "Request a demo"
    refute_match(/Join the waitlist/, response.body)
    %w[privacy terms security about].each { |slug| assert_select "footer a[href=?]", page_path(slug) }

    get "/ar"
    assert_select "h1", text: /التميّز والمخاطر والحوكمة/
  end

  test "the policy pages open in both languages without signing in" do
    %w[privacy terms security about].each do |slug|
      get page_path(slug)
      assert_response :success, slug
      assert_select "main h1"
      get page_path(slug, locale: :ar)
      assert_response :success
      assert_select "html[dir=rtl]"
    end
    get "/pages/nonsense"
    assert_response :not_found
  end
end
