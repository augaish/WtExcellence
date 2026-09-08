require "test_helper"

class AuthorityLevelTest < ActiveSupport::TestCase
  test "the six levels are defined in the order the governance documents use" do
    assert_equal %w[prepare review approve recommend authorize inform], AuthorityLevel::KEYS
    assert_equal (1..6).to_a, AuthorityLevel::KEYS.map { |key| AuthorityLevel.rank(key) }
  end

  test "every level has a label and a formal definition in both locales" do
    I18n.available_locales.each do |locale|
      AuthorityLevel::KEYS.each do |key|
        assert_predicate AuthorityLevel.label(key, locale), :present?,
          "#{key} has no #{locale} label"
        assert_predicate AuthorityLevel.description(key, locale), :present?,
          "#{key} has no #{locale} description"
      end
    end
  end

  test "carrying prepare, review and authorize on one item is a conflict" do
    assert AuthorityLevel.segregation_conflict?(%w[prepare review authorize])
    assert AuthorityLevel.segregation_conflict?(%w[prepare review authorize inform])
  end

  test "carrying only some of the segregated levels is allowed" do
    assert_not AuthorityLevel.segregation_conflict?(%w[prepare review])
    assert_not AuthorityLevel.segregation_conflict?(%w[review authorize])
    assert_not AuthorityLevel.segregation_conflict?(%w[recommend inform])
  end

  test "every lifecycle stage names a level it exercises, except the branch" do
    PpStage::KEYS.each do |key|
      level = PpStage.level_of(key)

      if PpStage.branch_stage?(key)
        assert_nil level, "#{key} is a branch and should exercise no authority level"
      else
        assert AuthorityLevel.exists?(level), "#{key} names an unknown level: #{level.inspect}"
      end
    end
  end

  test "final approval is the stage that exercises the authorize level" do
    assert_equal AuthorityLevel::FINAL_KEY, PpStage.level_of("s4_final")
  end
end
