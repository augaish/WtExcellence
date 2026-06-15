require "test_helper"

class AiActionCreditTest < ActiveSupport::TestCase
  test "ensure_defaults! creates missing credit rows with defaults" do
    AiActionCredit.delete_all

    AiActionCredit.ensure_defaults!

    CreditService::CREDIT_COSTS.each do |action_type, cost|
      credit = AiActionCredit.find_by(action_type: action_type)
      assert_not_nil credit, "Expected credit for #{action_type} to exist"
      assert_equal cost, credit.credit_cost, "Expected cost for #{action_type} to equal #{cost}"
      assert credit.display_name.present?, "Expected display name for #{action_type} to be present"
    end
  end
end

