require "test_helper"

class PpProcessAuthorityTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Matrix Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @process = @company.pp_processes.create!(name_en: "Procurement", level: 1)
    @authority = @process.authorities.create!(item: "Direct purchase", decision: "Award below SAR 1m")
  end

  test "a row must describe an item or a decision" do
    blank = @process.authorities.new

    assert_not blank.valid?
    assert_predicate blank.errors[:decision], :present?
  end

  test "an assignment must name a holder and a known level" do
    nameless = @authority.assignments.new(level: "authorize")
    assert_not nameless.valid?
    assert_predicate nameless.errors[:holder_title], :present?

    unknown_level = @authority.assignments.new(level: "rubber_stamp", holder_title: "Director")
    assert_not unknown_level.valid?
    assert_predicate unknown_level.errors[:level], :present?
  end

  test "exactly one holder may carry the final authorization" do
    @authority.assignments.create!(level: "prepare", holder_title: "Procurement Officer")
    assert_not @authority.reload.single_authorizer?, "no authorizer means nobody can decide"

    @authority.assignments.create!(level: "authorize", holder_title: "Procurement Director")
    assert @authority.reload.single_authorizer?

    @authority.assignments.create!(level: "authorize", holder_title: "Finance Director")
    assert_not @authority.reload.single_authorizer?, "two authorizers means nobody knows who decides"
  end

  test "one holder preparing, reviewing and authorizing the same decision is a breach" do
    %w[prepare review authorize].each do |level|
      @authority.assignments.create!(level: level, holder_title: "Procurement Director")
    end

    assert_includes @authority.reload.segregation_breaches, "procurement director"
  end

  test "the same holder across separate levels is not a breach" do
    @authority.assignments.create!(level: "prepare", holder_title: "Procurement Officer")
    @authority.assignments.create!(level: "review", holder_title: "Procurement Officer")
    @authority.assignments.create!(level: "authorize", holder_title: "Procurement Director")

    assert_empty @authority.reload.segregation_breaches
  end

  test "a condition is stored as data rather than as a footnote marker" do
    assignment = @authority.assignments.create!(level: "review", holder_title: "Legal Affairs",
      condition: "Where the contract exceeds one year")

    assert_equal "Where the contract exceeds one year", assignment.condition
  end

  test "an assignment reports its level in the reader's language" do
    assignment = @authority.assignments.create!(level: "authorize", holder_title: "Director")

    assert_equal "اعتماد", assignment.level_label(:ar)
    assert_equal "Authorize", assignment.level_label(:en)
  end
end
