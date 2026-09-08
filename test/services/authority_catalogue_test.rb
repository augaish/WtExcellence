require "test_helper"

# Suggestions, never seeded data: a matrix states who may decide what in one
# particular organisation.
class AuthorityCatalogueTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Cat Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
  end

  test "every suggestion is named in both languages" do
    I18n.available_locales.each do |locale|
      AuthorityCatalogue.categories(locale).each do |category|
        assert_predicate category[:name], :present?, "#{category[:key]} has no #{locale} name"
        category[:authorities].each do |authority|
          assert_predicate authority[:name], :present?, "#{authority[:key]} has no #{locale} name"
        end
      end
    end
  end

  test "nothing exists until a company asks for it" do
    assert_equal 0, @company.authority_categories.count
    assert_equal 0, @matrix.authorities.count
  end

  test "applying a suggestion creates ordinary editable records" do
    created = AuthorityCatalogue.apply(@matrix, category_keys: %w[financial])

    assert_equal 1, created[:categories]
    category = @company.authority_categories.sole
    assert_equal "Financial affairs", category.name_en
    assert_equal "الشؤون المالية", category.name_ar

    authorities = @matrix.reload.authorities
    assert_equal created[:authorities], authorities.count
    assert authorities.all? { |a| a.authority_category == category }

    # Ordinary data: it can be renamed and deleted like anything else.
    authorities.first.update!(name_en: "Our own wording")
    assert_equal "Our own wording", authorities.first.reload.name_en
  end

  test "no holder is ever suggested" do
    AuthorityCatalogue.apply(@matrix, category_keys: %w[procurement])

    @matrix.reload.authorities.each do |authority|
      assert_empty authority.assignments,
        "who decides is the organisation's judgement and must never be guessed"
    end
  end

  test "asking twice does not duplicate categories or authorities" do
    first = AuthorityCatalogue.apply(@matrix, category_keys: %w[financial])
    second = AuthorityCatalogue.apply(@matrix, category_keys: %w[financial])

    assert_operator first[:categories], :>, 0
    assert_equal 0, second[:categories]
    assert_equal 0, second[:authorities]
    assert_equal 1, @company.authority_categories.count
  end

  test "an unknown key is ignored rather than raising" do
    created = AuthorityCatalogue.apply(@matrix, category_keys: %w[not_a_category])

    assert_equal 0, created[:categories]
  end

  test "authorities are numbered in sequence as they are added" do
    AuthorityCatalogue.apply(@matrix, category_keys: %w[financial])
    numbers = @matrix.reload.authorities.map(&:number)

    assert_equal numbers.uniq, numbers, "each authority needs its own number"
    assert_equal numbers.sort, numbers
  end
end
